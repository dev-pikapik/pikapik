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
        /// The name of pikapik's virtual display while it shows the monitor: System Settings lists it as one more screen.
        var virtualName: String?

        func looksLike(_ percent: Int) -> (width: Int, height: Int) {
            DisplayScaleMath.looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
        }
    }

    /// notBack: going back to the size before the change failed, whatever the reason; dark: the monitor, by its name,
    /// did not come back after pikapik turned it off and on.
    enum Problem: Equatable { case unavailable, refused, lost, notBack, dark(String) }
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
    /// Id changes since the last wake or choice (see `renamed`).
    @ObservationIgnored private var renames: [CGDirectDisplayID: Int] = [:]
    /// While the screens sleep a mirror reads as ended; nothing is put back until they wake.
    @ObservationIgnored private var screensAsleep = false
    /// The monitor pikapik turns off and on so that macOS reads its new sizes: left alone until it is back.
    @ObservationIgnored private var reconnecting: CGDirectDisplayID?
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
                    if name == NSWorkspace.didWakeNotification {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { DisplayScale.shared.rescue() } }
                    }
                    // macOS ends the mirror itself as the screens wake: no sign that something else holds the monitor.
                    DisplayScale.shared.repaired = [:]
                    DisplayScale.shared.attempts = [:]
                    DisplayScale.shared.renames = [:]
                    DisplayScale.shared.screensChanged()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DisplayScale.shared.screensChanged() }
        }
        recheck()
    }

    /// Turns on a monitor pikapik left off, when it crashed or the monitor did not come back: at launch and after a
    /// wake, by the main copy only, as a second call while a monitor comes back starts its link over.
    func rescue() {
        guard MainCopy.canAct, reconnecting == nil else { return }
        turnOnMarked(now: false)
    }

    /// The marker stays until `refresh` sees the monitor lit, so every launch and wake tries again until then.
    private func turnOnMarked(now: Bool) {
        guard let marker = UserDefaults.standard.dictionary(forKey: PreferenceKey.displayScaleReconnecting) else { return }
        // A monitor that is off has no name, so the marker keeps who it is.
        let number = { (key: String) in (marker[key] as? NSNumber)?.uint32Value ?? 0 }
        Log.note("DisplayScale: turning on the monitor \(String(format: "%x-%x", number("vendor"), number("product"))) pikapik turned off")
        let enable = { DisplayScaler.enable(vendor: number("vendor"), product: number("product"), serial: number("serial"), lastID: number("id")) }
        if now { enable() } else { DispatchQueue.global().async { enable() } }
    }

    /// Every monitor back to its own picture: on quit, and when this copy stops being the main one.
    func release() {
        generation += 1
        // Quitting or handing over while a monitor is off: it comes back on before anything else.
        if reconnecting != nil {
            reconnecting = nil
            turnOnMarked(now: true)
            Brightness.shared.hold(false)
        }
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
        renames = [:]
    }

    func refresh() {
        var found: [Monitor] = []
        var next: [Monitor.ID: DisplayScaler] = [:]
        var builtIn = false
        let saved = Self.saved
        let displays = VirtualDisplay.onlineDisplays()
        // A monitor pikapik left dark that is lit again, by pikapik or a replug, needs no more turning on. Matched by
        // id, as its twin with the same serial number may be the lit one.
        if reconnecting == nil, let marker = UserDefaults.standard.dictionary(forKey: PreferenceKey.displayScaleReconnecting),
           let id = (marker["id"] as? NSNumber)?.uint32Value, displays.contains(id), CGDisplayIsAsleep(id) == 0 {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.displayScaleReconnecting)
        }
        // A virtual display named exactly as its monitor, as pikapik 1.57.0 and older made them and another copy may
        // still hold during a hand-over, makes macOS number both names: "S34CG50 (1)".
        let numbered = Set(displays.compactMap { id in Self.physicalDisplay(of: id) == id ? nil : Self.physicalDisplay(of: id) })
        for display in displays {
            if CGDisplayIsBuiltin(display) != 0 { builtIn = true; continue }
            // Its modes change while it comes back: it is read once it has.
            if display == reconnecting { continue }
            // pikapik's own virtual displays stay out, also in the moment their monitor is gone.
            guard !scalers.values.contains(where: { $0.virtual?.id == display }), Self.physicalDisplay(of: display) == display else { continue }
            let (id, key, unit) = identity(of: display, among: displays)
            if !numbered.contains(display), let screen = NSScreen.screens.first(where: { $0.displayID == display }) { names[id] = screen.localizedName }
            // Its id changed before screensChanged saw it; the scaler under the old id is released below.
            if scalers[id]?.display != display, let old = scalers.first(where: { $0.value.display == display }) { renamed(old.value, from: old.key, to: id) }
            var scaler = scalers[id].flatMap { keeps($0, display, id) ? $0 : nil }
            // A monitor in a mirror set pikapik did not make is never touched.
            if scaler == nil, CGDisplayIsInMirrorSet(display) == 0 { scaler = DisplayScaler(display: display, name: names[id] ?? "", unit: unit) }
            guard let native = scaler.map({ (width: $0.nativeWidth, height: $0.nativeHeight) })
                ?? DisplayScaler.native(in: DisplayScaler.modes(of: display)).map({ (width: $0.pixelWidth, height: $0.pixelHeight) })
            else { continue }
            next[id] = scaler
            // The monitor's own modes fit its port, as macOS offers only those; pikapik's own sizes fit the port's pipe.
            let pipe = DisplayScaleMath.steps(nativeWidth: native.width, nativeHeight: native.height, maxBackingWidth: DisplayScaler.pipeWidth(
                vendor: CGDisplayVendorNumber(display), product: CGDisplayModelNumber(display), serial: CGDisplaySerialNumber(display)))
            let own = DisplayScaleMath.steps(nativeWidth: native.width, nativeHeight: native.height).filter { scaler?.nativeMode($0) != nil }
            let steps = Set(pipe + own).sorted()
                .filter { $0 == 100 || scaler?.nativeMode($0) != nil || VirtualDisplay.isAvailable }
            let master = CGDisplayMirrorsDisplay(display)
            let shown = master == scaler?.virtual?.id ? master : display
            let measured = DisplayScaleMath.percent(nativeWidth: native.width, looksLikeWidth: CGDisplayCopyDisplayMode(shown)?.width ?? native.width)
            let usual = scaler?.original.map { DisplayScaleMath.percent(nativeWidth: native.width, looksLikeWidth: $0.width) } ?? measured
            found.append(Monitor(
                id: id, displayID: display, name: names[id] ?? scaler?.name ?? "", nativeWidth: native.width, nativeHeight: native.height,
                millimeters: scaler?.millimeters ?? CGDisplayScreenSize(display), steps: steps,
                virtualSteps: Set(steps.filter { $0 != 100 && scaler?.nativeMode($0) == nil }),
                current: scaler.flatMap { $0.holds ? $0.percent : nil } ?? measured, usual: usual,
                stored: saved[id] ?? unit.flatMap { _ in DisplayScaleMath.twinSize(saved: saved, key: key, online: Set(displays.map { identity(of: $0, among: displays).id })) },
                available: scaler != nil && (CGDisplayIsInMirrorSet(display) == 0 || master == scaler?.virtual?.id), virtualName: scaler?.virtual?.name))
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
        renames[monitor.displayID] = nil
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
        // Kept at its own picture, the monitor needs no entry: it shows that size without pikapik. One of two identical
        // monitors keeps it all the same, or it would take a size saved for its twin (`DisplayScaleMath.twinSize`).
        let own = scalers[pending.monitor].map { !$0.changed && $0.unit == nil } ?? false
        saved[pending.monitor] = own ? nil : pending.to
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

    /// A monitor's id: vendor-model-serial (`key`), as Brightness keys it. Two monitors of one model with the same serial
    /// number (some report 0) add their unit numbers, and so do their virtual displays. This Mac remembers such a model
    /// for good, so one of them alone keeps its id, its size and its virtual display; a model it never saw twice keeps
    /// the id it always had.
    private func identity(of display: CGDirectDisplayID, among displays: [CGDirectDisplayID]) -> (id: Monitor.ID, key: String, unit: UInt32?) {
        let key = { (display: CGDirectDisplayID) in "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))" }
        let own = key(display), unit = CGDisplayUnitNumber(display)
        var twins = Set(UserDefaults.standard.stringArray(forKey: PreferenceKey.displayScaleTwins) ?? [])
        if !twins.contains(own), displays.filter({ key($0) == own }).count > 1 {
            twins.insert(own)
            UserDefaults.standard.set(twins.sorted(), forKey: PreferenceKey.displayScaleTwins)
        }
        return twins.contains(own) ? ("\(own)-\(unit)", own, unit) : (own, own, nil)
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
            let wanted = scaler.percent ?? monitor.stored ?? monitor.current
            // A saved size this port can't show sharply, say 125 % on a 5120-pixel pipe, becomes the nearest one it can, the smaller of two as near.
            let target = monitor.steps.contains(wanted) || wanted == monitor.current
                ? wanted : monitor.steps.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
            // A size only a virtual display shows gets the monitor's own mode instead once the fan helper adds it.
            let sizes = monitor.virtualSteps.contains(target) ? scaler.overrideSizes : []
            let ask = Self.lacks(sizes, asked: Self.asked[monitor.id])
            guard ask || target != monitor.current || !scaler.holds, monitor.steps.contains(target) else { continue }
            busy = monitor.id
            forgive(allBut: display, mirrors: !scaler.changed)
            Task {
                if ask, await addNativeModes(monitor, scaler, sizes, target) {
                    busy = nil
                    return recheck()
                }
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

    /// A monitor that went away, or that goes by another id because an identical one came for the first time or its unit
    /// number changed, loses its virtual display at once; the rest waits until the screens settle, so it is read again
    /// showing its own picture.
    private func screensChanged() {
        let online = VirtualDisplay.onlineDisplays()
        for (id, scaler) in scalers {
            let now = online.contains(scaler.display) ? identity(of: scaler.display, among: online).id : nil
            if now == id { continue }
            if let now { renamed(scaler, from: id, to: now) } else if scaler.changed { Log.note("DisplayScale: \(names[id] ?? scaler.name) went away") }
            scaler.release()
            scalers[id] = nil
            settled.remove(scaler.display)
            if let pending, pending.monitor == id {
                failure = Failure(monitor: now ?? id, percent: pending.to, problem: .lost)
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

    /// A monitor that goes by another id is settled again under it. A unit number should hold while the monitor stays
    /// connected; if it moved with every change of the screens, setting the size would change them again without end,
    /// so the third change leaves the monitor at its own picture until a wake or a choice.
    private func renamed(_ scaler: DisplayScaler, from old: Monitor.ID, to new: Monitor.ID) {
        let display = scaler.display, count = renames[display, default: 0] + 1
        renames[display] = count
        settled.remove(display)
        guard count <= 3 else { return }
        Log.note("DisplayScale: \(names[old] ?? scaler.name) goes by \(new) instead of \(old)")
        guard count == 3 else { return }
        Log.note("DisplayScale: \(names[old] ?? scaler.name) changed its id three times, left at its own picture until a wake or a choice")
        failed.insert(display)
        attempts[display] = 3
    }

    private static var asked: [Monitor.ID: [Int]] {
        UserDefaults.standard.dictionary(forKey: PreferenceKey.displayScaleModes) as? [Monitor.ID: [Int]] ?? [:]
    }

    /// Whether `sizes` holds one not asked for yet. Asked once, a size stays in the file: macOS may list only some, and
    /// a file written anew with only the missing ones would take the others away, the monitor dark each time.
    private static func lacks(_ sizes: [Int], asked: [Int]?) -> Bool {
        !Set(pairs(sizes)).isSubset(of: pairs(asked ?? []))
    }

    private static func pairs(_ sizes: [Int]) -> [[Int]] {
        stride(from: 0, to: sizes.count - 1, by: 2).map { [sizes[$0], sizes[$0 + 1]] }
    }

    /// Asks the fan helper for the sizes the monitor lacks, then turns the monitor off and on once, so macOS reads them.
    /// True when it went off (the next refresh reads it anew and takes its own mode), false when it keeps the virtual
    /// display for now: no helper, or not a safe moment; the sizes then come with the next reconnection or restart.
    private func addNativeModes(_ monitor: Monitor, _ scaler: DisplayScaler, _ sizes: [Int], _ target: Int) async -> Bool {
        // Spent first: one try per set of sizes, also across a crash, so the monitor never goes dark in a loop.
        var asked = Self.asked
        let all = Set(Self.pairs(sizes) + Self.pairs(asked[monitor.id] ?? [])).sorted { ($0[0], $0[1]) > ($1[0], $1[1]) }.flatMap { $0 }
        asked[monitor.id] = all
        UserDefaults.standard.set(asked, forKey: PreferenceKey.displayScaleModes)
        let model = String(format: "%x-%x", scaler.vendor, scaler.product)
        guard await FanControl.shared.addScaleModes(vendor: scaler.vendor, product: scaler.product, sizes: all) == true else { return false }
        Log.note("DisplayScale: \(monitor.name) sizes written for \(model): \(all)")
        let display = scaler.display
        guard canTurnOff(display), scalers[monitor.id] === scaler else {
            Log.note("DisplayScale: \(monitor.name) sizes appear after the monitor reconnects")
            return false
        }
        // The monitor shows its own picture while it is off: a mirror would leave the virtual display behind as an
        // invisible screen that catches the windows.
        try? await scaler.restore()
        guard CGDisplayMirrorsDisplay(display) == kCGNullDirectDisplay, canTurnOff(display) else {
            Log.note("DisplayScale: \(monitor.name) sizes appear after the monitor reconnects")
            return false
        }
        let managed = Set(scalers.values.filter(\.changed).map(\.display))
        let placements = DisplayScaler.placements(keepingModesOf: managed)
        scaler.release()
        scalers[monitor.id] = nil
        settled.remove(display)
        reconnecting = display
        Brightness.shared.hold(true)
        UserDefaults.standard.set(["vendor": scaler.vendor, "product": scaler.product, "serial": scaler.serial, "unit": scaler.unit ?? 0,
                                   "id": display, "date": Date()], forKey: PreferenceKey.displayScaleReconnecting)
        Log.note("DisplayScale: \(monitor.name) turns off and on to read its new sizes")
        let back = await DisplayScaler.reconnect(display)
        // release() turned it on meanwhile: this copy quits or hands over.
        guard reconnecting == display else { return true }
        if let back {
            DisplayScaler.putBack(placements, renamed: [display: back])
            UserDefaults.standard.removeObject(forKey: PreferenceKey.displayScaleReconnecting)
            Log.note("DisplayScale: \(monitor.name) is back")
        } else {
            // The marker stays: the next launch or wake turns it on again.
            failure = Failure(monitor: monitor.id, percent: target, problem: .dark(monitor.name))
            Log.note("DisplayScale: \(monitor.name) did not come back after turning on")
        }
        // Brightness waits for the link to settle, unless another monitor is off by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated { if DisplayScale.shared.reconnecting == nil { Brightness.shared.hold(false) } }
        }
        reconnecting = nil
        // A wake meanwhile skipped its rescue: one more try once the link had time.
        if back == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { MainActor.assumeIsolated { DisplayScale.shared.rescue() } }
        }
        return true
    }

    /// A safe moment to turn a monitor off: the screens awake, nothing else under way, no display captured, and another screen stays lit
    /// for the windows, the menu bar and the pointer (one that shows pikapik's virtual display counts).
    private func canTurnOff(_ display: CGDirectDisplayID) -> Bool {
        let online = VirtualDisplay.onlineDisplays()
        guard MainCopy.canAct, !screensAsleep, reconnecting == nil, pending == nil, DisplayScaler.canReconnect, online.contains(display),
              CGDisplayIsAsleep(display) == 0 else { return false }
        // CGDisplayIsCaptured is unavailable in Swift; a captured display (a game, a lock screen) shows a window at the
        // shielding level, and a window list that can't be read counts as captured.
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              !windows.contains(where: { ($0[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGShieldingWindowLevel()) }) else { return false }
        let master = CGDisplayMirrorsDisplay(display)
        return online.contains { other in
            let shows = CGDisplayMirrorsDisplay(other)
            return other != display && other != master && shows != display && (master == kCGNullDirectDisplay || shows != master)
                && Self.physicalDisplay(of: other) == other && (1...0xFFFF).contains(CGDisplayVendorNumber(other)) && CGDisplayIsAsleep(other) == 0
        }
    }

    /// Lets the monitors that show a size through a virtual display ask for their own modes again: the fan helper was
    /// just installed, so a monitor asked for before without one tries once more.
    func addSizesSoon() {
        let virtual = scalers.filter { $0.value.virtual != nil }
        var asked = Self.asked
        for id in virtual.keys { asked[id] = nil }
        UserDefaults.standard.set(asked, forKey: PreferenceKey.displayScaleModes)
        settled.subtract(virtual.values.map(\.display))
        refresh()
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
