import AppKit

/// Shows a monitor larger and still sharp: macOS draws the desktop at twice the size it looks like, and the
/// monitor shows that picture.
@MainActor @Observable final class DisplayScale {
    static let shared = DisplayScale()

    struct Monitor: Identifiable, Equatable {
        let id: String
        var displayID: CGDirectDisplayID
        var name: String
        var nativeWidth: Int, nativeHeight: Int
        var millimeters: CGSize
        var steps: [Int]
        var virtualSteps: Set<Int>
        var current: Int
        /// The size the monitor has without pikapik, the one it goes back to when pikapik quits.
        var usual: Int
        var stored: Int?
        var available: Bool

        func looksLike(_ percent: Int) -> (width: Int, height: Int) {
            DisplayScaleMath.looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
        }
    }

    /// notBack: going back to the size before the change failed, whatever the reason.
    enum Problem: Equatable { case unavailable, refused, lost, notBack }
    struct Failure: Equatable { let monitor: Monitor.ID; let percent: Int; let problem: Problem }
    struct Pending: Equatable { let monitor: Monitor.ID; let from: Int; let to: Int; let deadline: Date }

    private(set) var monitors: [Monitor] = []
    private(set) var hasBuiltIn = false
    private(set) var pending: Pending?
    private(set) var busy: Monitor.ID?
    private(set) var failure: Failure?
    @ObservationIgnored private var names: [Monitor.ID: String] = [:]
    @ObservationIgnored private var scalers: [Monitor.ID: DisplayScaler] = [:]
    /// Monitors that show what they should; any other gets its saved step once, as it appears.
    @ObservationIgnored private var settled: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var failed: Set<CGDirectDisplayID> = []
    /// Tries in a row that did not work: after three, a monitor waits for a wake or a choice in Settings. A monitor that
    /// goes away keeps its count, because a failed try can make it drop off for a moment.
    @ObservationIgnored private var attempts: [CGDirectDisplayID: Int] = [:]
    /// When a broken mirror was last put back: broken again within a minute, the monitor keeps its own picture.
    @ObservationIgnored private var repaired: [CGDirectDisplayID: Date] = [:]
    /// While the screens sleep a mirror reads as ended; nothing is put back until they wake.
    @ObservationIgnored private var screensAsleep = false
    /// The pending change started from the monitor's own picture, so going back ends pikapik's changes.
    @ObservationIgnored private var fromOwn = false
    @ObservationIgnored private var deadline: DispatchWorkItem?
    @ObservationIgnored private var settle: DispatchWorkItem?
    @ObservationIgnored private var generation = 0

    private init() {}

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DisplayScale.shared.screensAsleep = true }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.screensDidWakeNotification { DisplayScale.shared.screensAsleep = false }
                    // macOS ends the mirror itself as the screens wake: no sign that something else holds the monitor.
                    DisplayScale.shared.repaired = [:]
                    DisplayScale.shared.attempts = [:]
                    DisplayScale.shared.screensChanged()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DisplayScale.shared.screensChanged() }
        }
        recheck()
    }

    /// Every monitor back to its own picture: on quit, and when this copy stops being the main one.
    func release() {
        generation += 1
        settle?.cancel()
        if pending != nil { clearPending() }
        for (id, scaler) in scalers {
            if scaler.changed { Log.note("DisplayScale: \(names[id] ?? scaler.name) back to its own picture") }
            scaler.release()
        }
        scalers = [:]
        settled = []
        failed = []
        attempts = [:]
    }

    func refresh() {
        var found: [Monitor] = []
        var next: [Monitor.ID: DisplayScaler] = [:]
        var builtIn = false
        let saved = Self.saved
        let displays = VirtualDisplay.onlineDisplays()
        // While one of pikapik's virtual displays of a monitor is online, macOS numbers both names: "S34CG50 (1)".
        let numbered = Set(displays.compactMap { id in Self.physicalDisplay(of: id) == id ? nil : Self.physicalDisplay(of: id) })
        let key = { (display: CGDirectDisplayID) in "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))" }
        let keys = displays.map(key)
        for display in displays {
            if CGDisplayIsBuiltin(display) != 0 { builtIn = true; continue }
            // pikapik's own virtual displays stay out, also in the moment their monitor is gone.
            guard !scalers.values.contains(where: { $0.virtual?.id == display }), Self.physicalDisplay(of: display) == display else { continue }
            // Two monitors of one model with the same serial number: their unit numbers tell them apart, and they keep
            // to their own modes, because their virtual displays would share one identity.
            let twin = keys.filter { $0 == key(display) }.count > 1
            let id = twin ? "\(key(display))-\(CGDisplayUnitNumber(display))" : key(display)
            if !numbered.contains(display), let screen = NSScreen.screens.first(where: { $0.displayID == display }) { names[id] = screen.localizedName }
            var scaler = scalers[id].flatMap { keeps($0, display, id) ? $0 : nil }
            // A monitor in a mirror set pikapik did not make is never touched.
            if scaler == nil, CGDisplayIsInMirrorSet(display) == 0 { scaler = DisplayScaler(display: display, name: names[id] ?? "") }
            guard let native = scaler.map({ (width: $0.nativeWidth, height: $0.nativeHeight) })
                ?? DisplayScaler.native(in: DisplayScaler.modes(of: display)).map({ (width: $0.pixelWidth, height: $0.pixelHeight) })
            else { continue }
            next[id] = scaler
            let steps = DisplayScaleMath.steps(nativeWidth: native.width, nativeHeight: native.height)
                .filter { $0 == 100 || scaler?.nativeMode($0) != nil || VirtualDisplay.isAvailable && !twin }
            let master = CGDisplayMirrorsDisplay(display)
            let shown = master == scaler?.virtual?.id ? master : display
            let measured = DisplayScaleMath.percent(nativeWidth: native.width, looksLikeWidth: CGDisplayCopyDisplayMode(shown)?.width ?? native.width)
            let usual = scaler?.original.map { DisplayScaleMath.percent(nativeWidth: native.width, looksLikeWidth: $0.width) } ?? measured
            found.append(Monitor(
                id: id, displayID: display, name: names[id] ?? scaler?.name ?? "", nativeWidth: native.width, nativeHeight: native.height,
                millimeters: scaler?.millimeters ?? CGDisplayScreenSize(display), steps: steps,
                virtualSteps: Set(steps.filter { $0 != 100 && scaler?.nativeMode($0) == nil }),
                current: scaler.flatMap { $0.holds ? $0.percent : nil } ?? measured, usual: usual, stored: saved[id],
                available: scaler != nil && (CGDisplayIsInMirrorSet(display) == 0 || master == scaler?.virtual?.id)))
        }
        for (id, old) in scalers where next[id] !== old { old.release() }
        scalers = next
        // A monitor in someone else's mirror counts as appearing again once it is free.
        settled.formIntersection(Set(found.filter(\.available).map(\.displayID)))
        failed.formIntersection(Set(found.map(\.displayID)))
        // Left to right, as System Settings shows them.
        found.sort {
            let a = CGDisplayBounds($0.displayID), b = CGDisplayBounds($1.displayID)
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
        if found != monitors { monitors = found }
        if builtIn != hasBuiltIn { hasBuiltIn = builtIn }
        settleNext()
    }

    func choose(_ percent: Int, for id: Monitor.ID) {
        guard MainCopy.canAct, busy == nil, pending == nil, let monitor = monitors.first(where: { $0.id == id }),
              monitor.available, monitor.steps.contains(percent), percent != monitor.current, let scaler = scalers[id] else { return }
        busy = id
        forgive(allBut: monitor.displayID)
        if failure?.monitor == id { failure = nil }
        fromOwn = !scaler.changed
        Task {
            do {
                try await scaler.show(percent)
                settled.insert(monitor.displayID)
                failed.remove(monitor.displayID)
                attempts[monitor.displayID] = nil
                pending = Pending(monitor: id, from: monitor.current, to: percent, deadline: Date().addingTimeInterval(15))
                let work = DispatchWorkItem { MainActor.assumeIsolated { DisplayScale.shared.goBack() } }
                deadline = work
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 15, execute: work)
                Log.note("DisplayScale: \(monitor.name) at \(percent)%, waiting for Keep")
            } catch is CancellationError {
            } catch {
                failure = Failure(monitor: id, percent: percent, problem: Self.problem(error))
                Log.note("DisplayScale: \(monitor.name) did not take \(percent)%: \(error)")
            }
            busy = nil
            refresh()
            if pending != nil { DisplayScaleConfirm.show() }
        }
    }

    func keep() {
        guard let pending else { return }
        var saved = Self.saved
        // Kept at its own picture, the monitor needs no entry: it shows that size without pikapik.
        saved[pending.monitor] = scalers[pending.monitor]?.changed == false ? nil : pending.to
        UserDefaults.standard.set(saved, forKey: PreferenceKey.displayScale)
        clearPending()
        Log.note("DisplayScale: \(names[pending.monitor] ?? "") keeps \(pending.to)%")
        refresh()
    }

    func goBack() {
        guard let pending else { return }
        clearPending()
        guard let scaler = scalers[pending.monitor] else { return refresh() }
        busy = pending.monitor
        forgive(allBut: scaler.display)
        let own = fromOwn
        Task {
            do {
                if own { try await scaler.restore() } else { try await scaler.show(pending.from) }
                Log.note("DisplayScale: \(scaler.name) back to \(pending.from)%")
            } catch is CancellationError {
            } catch {
                failure = Failure(monitor: pending.monitor, percent: pending.from, problem: .notBack)
                Log.note("DisplayScale: \(scaler.name) did not go back to \(pending.from)%: \(error)")
            }
            busy = nil
            refresh()
        }
    }

    func screen(for id: Monitor.ID) -> NSScreen? {
        guard let display = monitors.first(where: { $0.id == id })?.displayID else { return nil }
        return NSScreen.screens.first { Self.physicalDisplay(of: $0.displayID) == display }
    }

    /// The monitor behind a display: a virtual display pikapik made maps to the monitor that shows it.
    nonisolated static func physicalDisplay(of id: CGDirectDisplayID) -> CGDirectDisplayID {
        VirtualDisplay.physical(of: id)
    }

    private static var saved: [Monitor.ID: Int] {
        UserDefaults.standard.dictionary(forKey: PreferenceKey.displayScale) as? [Monitor.ID: Int] ?? [:]
    }

    /// A monitor is read again on every refresh, except while it shows something of pikapik's: its mirror, even a
    /// broken one that is put back, or a mode nobody replaced since but macOS itself. A mode someone else set is theirs.
    private func keeps(_ scaler: DisplayScaler, _ display: CGDirectDisplayID, _ id: Monitor.ID) -> Bool {
        guard scaler.display == display else { return false }
        if busy == id { return true }
        if let virtual = scaler.virtual { return CGDisplayIsInMirrorSet(display) == 0 || CGDisplayMirrorsDisplay(display) == virtual.id }
        return scaler.changed && (scaler.holds || scaler.putBack)
    }

    /// macOS puts every monitor's own mode back, and may end a mirror, whenever a virtual display comes or goes: what
    /// pikapik's change on another monitor undoes is put back again, not counted as broken twice. Putting a monitor's
    /// own step back spares the mirrors: it changes the displays only when its virtual display went away, and two such
    /// repairs that keep ending each other's mirror still give up.
    private func forgive(allBut display: CGDirectDisplayID, mirrors: Bool = true) {
        for scaler in scalers.values where scaler.display != display && (mirrors || scaler.virtual == nil) { repaired[scaler.display] = nil }
    }

    /// Puts the saved step on a monitor that just appeared, or a broken mirror or 2x mode back, one monitor at a time.
    private func settleNext() {
        guard MainCopy.canAct, busy == nil, pending == nil, !screensAsleep else { return }
        let saved = Self.saved
        for monitor in monitors {
            let display = monitor.displayID
            // A monitor that becomes free counts as appearing; one that sleeps is judged when it wakes.
            guard monitor.available, let scaler = scalers[monitor.id], CGDisplayIsAsleep(display) == 0 else { continue }
            if scaler.changed, settled.contains(display) {
                switch DisplayScaleMath.mend(holds: scaler.holds, lastRepair: repaired[display], now: Date()) {
                case .keep: break
                case .giveUp:
                    failure = Failure(monitor: monitor.id, percent: scaler.percent ?? monitor.current, problem: .lost)
                    Log.note("DisplayScale: \(monitor.name) lost its larger picture twice in a minute, left as it is")
                    forgive(allBut: display)
                    scaler.release()
                    // Tried again after the next wake, which resets the tries.
                    failed.insert(display)
                    attempts[display] = 3
                    continue
                case .repair:
                    repaired[display] = Date()
                    settled.remove(display)
                }
            }
            guard !settled.contains(display), attempts[display, default: 0] < 3 else { continue }
            settled.insert(display)
            let target = scaler.percent ?? saved[monitor.id] ?? monitor.current
            guard target != monitor.current || !scaler.holds, monitor.steps.contains(target) else { continue }
            busy = monitor.id
            forgive(allBut: display, mirrors: !scaler.changed)
            Task {
                do {
                    try await scaler.show(target)
                    failed.remove(display)
                    attempts[display] = nil
                    if failure?.monitor == monitor.id, failure?.percent == target { failure = nil }
                    Log.note("DisplayScale: \(monitor.name) at \(target)%")
                } catch is CancellationError {
                } catch {
                    failed.insert(display)
                    attempts[display, default: 0] += 1
                    failure = Failure(monitor: monitor.id, percent: target, problem: Self.problem(error))
                    Log.note("DisplayScale: \(monitor.name) did not take \(target)%: \(error)")
                }
                busy = nil
                refresh()
            }
            return
        }
    }

    /// A monitor that went away loses its virtual display at once; the rest waits until the screens settle.
    private func screensChanged() {
        let online = VirtualDisplay.onlineDisplays()
        for (id, scaler) in scalers where !online.contains(scaler.display) {
            if scaler.changed { Log.note("DisplayScale: \(names[id] ?? scaler.name) went away") }
            scaler.release()
            scalers[id] = nil
            settled.remove(scaler.display)
            if let pending, pending.monitor == id {
                failure = Failure(monitor: id, percent: pending.to, problem: .lost)
                clearPending()
            }
        }
        settle?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { DisplayScale.shared.recheck() } }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Settles the monitors now, then tries the ones that failed again after 2 and 6 seconds, three tries in a row at
    /// most: every try changes the screens, which would start this again without end.
    private func recheck() {
        generation += 1
        let current = generation
        refresh()
        for delay in [2.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    let model = DisplayScale.shared
                    let again = model.failed.filter { model.attempts[$0, default: 0] < 3 }
                    guard current == model.generation, !again.isEmpty else { return }
                    model.settled.subtract(again)
                    model.failed.subtract(again)
                    model.refresh()
                }
            }
        }
    }

    private func clearPending() {
        deadline?.cancel()
        deadline = nil
        pending = nil
        DisplayScaleConfirm.hide()
    }

    private static func problem(_ error: Error) -> Problem {
        switch (error as? DisplayScaler.Refusal)?.reason {
        case .unavailable?: .unavailable
        case .lost?: .lost
        default: .refused
        }
    }
}
