import AppKit

/// On Apple silicon a monitor that mirrors a virtual display moves its pointer only when the virtual display draws a
/// new frame, and apps that are not active draw nothing as the pointer passes, so the pointer looked stuck until a
/// click. One invisible point on the scaled display under the pointer changes with every move, so a frame follows.
@MainActor enum PointerNudge {
    private static var displays: Set<CGDirectDisplayID> = []
    private static var monitors: [Any] = []
    private static var current: CGDirectDisplayID?
    private static var last = CGPoint(x: -1, y: -1)
    private static var white = false
    private static var looked = 0.0, due = false
    private static var flipped = 0.0, resting = false
    private static var keyed: Any?
    private static let dot: NSPanel = {
        let dot = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        dot.isOpaque = false
        dot.backgroundColor = .black
        dot.alphaValue = 0.01
        dot.hasShadow = false
        dot.ignoresMouseEvents = true
        dot.hidesOnDeactivate = false
        dot.canHide = false
        dot.isExcludedFromWindowsMenu = true
        dot.setAccessibilityElement(false)
        dot.level = .statusBar
        dot.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return dot
    }()

    /// A virtual display pikapik shows a monitor through came (true) or went (false).
    static func track(_ display: CGDirectDisplayID, _ shown: Bool) {
        if shown {
            displays.insert(display)
        } else {
            // The point leaves with its display; the next move over a display still scaled brings it back.
            displays.remove(display)
            current = nil
            dot.orderOut(nil)
        }
        if displays.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
        } else if monitors.isEmpty {
            let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            monitors = [NSEvent.addGlobalMonitorForEvents(matching: moves) { _ in MainActor.assumeIsolated { moved() } },
                        NSEvent.addLocalMonitorForEvents(matching: moves) { event in MainActor.assumeIsolated { moved() }; return event }]
                .compactMap { $0 }
            // While pikapik itself is the active app (Settings, the Keep panel), the moves are its own, which the global
            // monitor never sees; the local one sees them once the key window takes them.
            NSApp.keyWindow?.acceptsMouseMovedEvents = true
            keyed = keyed ?? NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { (note.object as? NSWindow)?.acceptsMouseMovedEvents = true }
            }
        }
    }

    /// A mouse polled 1000 times a second sends more moves than a monitor shows frames, so moves are taken at most 240
    /// times a second; a move inside that gap is taken when the gap ends, so the pointer never stops short.
    private static func moved() {
        guard !due else { return }
        let wait = looked + 1.0 / 240 - ProcessInfo.processInfo.systemUptime
        guard wait > 0 else { return nudge() }
        due = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { MainActor.assumeIsolated { due = false; nudge() } }
    }

    private static func nudge() {
        looked = ProcessInfo.processInfo.systemUptime
        // A game holding the pointer still sends moves while the pointer stays put: nothing to draw then.
        guard let point = CGEvent(source: nil)?.location, point != last else { return }
        last = point
        let under = displays.first { CGDisplayBounds($0).contains(point) }
        guard under != nil || current != nil else { return }
        if let under {
            let corner = FramePillPlace.cocoa(CGDisplayBounds(under), primaryHeight: NSScreen.screens.first?.frame.height ?? 0).origin
            if dot.frame.origin != corner || !dot.isVisible { dot.setFrameOrigin(corner); dot.orderFrontRegardless() }
        }
        current = under // the display the pointer just left draws once more, so its pointer leaves with it
        white.toggle()
        dot.backgroundColor = white ? .white : .black
        flipped = ProcessInfo.processInfo.systemUptime
        if !resting { resting = true; rest(after: 1) }
    }

    /// A second after the last change the point goes, so no window stays over a full-screen game that holds the pointer,
    /// and its going draws one more frame, which shows a pointer shape that changed after the last move. The next move
    /// brings it back.
    private static func rest(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let left = flipped + 1 - ProcessInfo.processInfo.systemUptime
                guard left <= 0 else { return rest(after: left) }
                resting = false
                current = nil
                dot.orderOut(nil)
            }
        }
    }
}
