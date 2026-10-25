import AppKit
import CoreAudio
import IOKit.ps
import SwiftUI

final class PetStage: NSObject {
    static let shared = PetStage()
    static let scale: CGFloat = 2.4
    static let width: CGFloat = 72
    static let height: CGFloat = 190
    static let ground: CGFloat = 4
    static let spill: CGFloat = 480

    private let launched = ProcessInfo.processInfo.systemUptime
    private var window: NSPanel?
    private var field: NSPanel?
    private var bubble: NSPanel?
    private var link: CADisplayLink?
    private let view = FigureView(PetPose()) { pose, night, fill in
        PetFigure.shadow(pose, fill: fill)
        PetFigure.draw(pose, night: night, fill: fill)
    }
    private let ballView = FigureView(BallPose(), paint: BallFigure.draw)
    private let grip = PetHand()
    private let ballGrip = PetHand()
    private var raised = false, tossed = false, hiddenUp = false, hiddenToss = false
    private var fake: CGPoint?
    private var anchor = CGPoint.zero
    private var grabbed = 0.0
    private var physics = PetPhysics(bounds: CGRect(x: 0, y: ground, width: 600, height: height - ground))
    private var ball = BallPhysics(bounds: CGRect(x: 0, y: ground, width: 600, height: height - ground), x: 300)
    private var press: CGPoint?
    private var drags = 0
    private var sunk: Set<Int> = []
    private var monitor: Any?
    private var chase = 0.0
    private var last: CFTimeInterval?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var asleep = false, locked = false, fullscreen = false
    private var home: CGDirectDisplayID = 0, court: CGDirectDisplayID = 0
    private var full: Set<CGDirectDisplayID> = []
    private var watchdog: Timer?
    private var blind: Timer?
    private var alarm: Timer?, peek: Timer?
    private var source: CFRunLoopSource?
    private var nextTalk: TimeInterval
    private var deck: [PetPhrase] = []
    private var phrase: PetPhrase?
    private var nudging = false
    private var ticked = 0.0
    private var felt = 0.0
    private var waited = false, petCovered = false, toyCovered = false
    private var lowPower = false, battery = false, hot = false
    private var blinked = 0.0, advanced = 0.0, nextAsk = 0.0
    private var hover = (point: CGPoint.zero, at: -Double.infinity)
    private var probe: (point: CGPoint, time: Double, layer: Int?)?
    private var snapshot: [[String: Any]]?
    private var docked: CGRect?
    private var frames: [CGRect] = []
    private var heard = (at: -Double.infinity, on: false)
    private var baked = PetPose()
    private var feelings = PetCues()
    private var cradled = 0.0, touched = ProcessInfo.processInfo.systemUptime
    private var nextCheer = 0.0, nextLook = 0.0, dull = Double.random(in: 20...40)
    private var eager: Double?, still: CGPoint?, stillAt = 0.0
    private var shown = -1
    private static let anyInput = CGEventType(rawValue: ~0)!

    private override init() {
        nextTalk = launched + .random(in: 600...840)
    }

    private let dev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    private var demo: String? {
        dev ? UserDefaults.standard.string(forKey: "pet-demo") : nil
    }

    private var progress: PetProgress? { demo == nil ? .shared : nil }

    func start() {
        guard window == nil else { return }
        let window = Self.panel(view, grip), field = Self.panel(ballView, ballGrip)
        self.window = window
        self.field = field
        feelings.begin(news: PetProgress.shared.news.count)

        let link = view.displayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link

        let workspace = NSWorkspace.shared.notificationCenter, local = NotificationCenter.default, distributed = DistributedNotificationCenter.default()
        watch(local, NSApplication.didChangeScreenParametersNotification) {
            $0.nextAsk = 0
            $0.layout()
        }
        watch(local, NSWindow.didChangeOcclusionStateNotification, window) { $0.checkFullscreen() }
        watch(local, NSWindow.didChangeOcclusionStateNotification, field) { $0.checkFullscreen() }
        watch(local, .NSProcessInfoPowerStateDidChange) { $0.power() }
        watch(local, ProcessInfo.thermalStateDidChangeNotification) { $0.power() }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.asleep = true }
        watch(workspace, NSWorkspace.screensDidWakeNotification) {
            $0.asleep = false
            $0.feelings.hello = true
        }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.locked = true }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.locked = false }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        watch(distributed, Notification.Name("com.apple.dock.prefchanged")) {
            $0.nextAsk = 0
            $0.shelter()
        }
        watch(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.physics.calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            watch(workspace, name) { stage in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    stage.nextAsk = 0
                    stage.shelter()
                    stage.stir()
                }
            }
        }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            watch(workspace, name) { stage in
                DispatchQueue.main.async { stage.checkFullscreen() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { stage.checkFullscreen() }
            }
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in self?.pressed(event.locationInWindow) }

        home = NSScreen.screens.first.map(Self.id) ?? 0
        court = home
        layout()
        let width = petScreen?.frame.width ?? physics.bounds.width
        physics = PetPhysics(bounds: physics.bounds, x: width * (demo == nil ? .random(in: 0.1...0.9) : 0.12), facing: demo == nil && Bool.random() ? -1 : 1)
        physics.calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ball = BallPhysics(bounds: physics.bounds, x: width * (demo == nil ? .random(in: 0.1...0.9) : 0.4))
        shelter()
        if let power = IOPSCreateLimitedPowerNotification({ _ in PetStage.shared.power() }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), power, .commonModes)
            source = power
        }
        power()
        reconcile()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        watchdog?.tolerance = 0.3
    }

    func stop() {
        raised = false
        tossed = false
        link?.invalidate()
        link = nil
        watchdog?.invalidate()
        watchdog = nil
        blind?.invalidate()
        blind = nil
        alarm?.invalidate()
        alarm = nil
        peek?.invalidate()
        peek = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        press = nil
        hideBubble()
        bubble = nil
        window?.orderOut(nil)
        window = nil
        field?.orderOut(nil)
        field = nil
        last = nil
        probe = nil
        waited = false
        nextAsk = 0
    }

    func jump() {
        guard window?.isVisible == true else { return }
        if !(lowPower && physics.wake()) { physics.jump() }
        stir()
    }

    func grab(at point: CGPoint, in panel: NSWindow?) {
        let origin = panel?.frame.origin ?? .zero
        func local(_ other: NSWindow?) -> CGPoint {
            CGPoint(x: point.x + origin.x - (other?.frame.minX ?? origin.x), y: point.y + origin.y - (other?.frame.minY ?? origin.y))
        }
        let airborne = !physics.grounded
        let lifted = physics.grab(at: local(window))
        guard lifted || ball.grab(at: local(field)) else { return }
        if lifted {
            progress?.add(.lifts)
            if airborne { progress?.add(.catches) }
            let now = ProcessInfo.processInfo.systemUptime
            cradled = now
            touched = now
            feel(.surprised, now)
        }
        NSCursor.closedHand.set()
        rise()
        place()
        stir()
    }

    func drop() {
        guard physics.state == .held || ball.held else { return }
        if physics.state == .held {
            let now = ProcessInfo.processInfo.systemUptime
            if hypot(physics.vx, physics.vy) < 300, now - cradled >= 0.5 {
                feel(.happy, now)
                progress?.add(.cuddles)
            }
        }
        physics.release()
        let carried = ball.held
        ball.release()
        if carried, hypot(ball.vx, ball.vy) >= BallPhysics.nudge { progress?.add(.plays) }
        NSCursor.arrow.set()
        stir()
    }

    private static var level: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private static func panel(_ figure: NSView, _ hand: PetHand) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = PetHand()
        panel.contentView?.wantsLayer = true
        panel.contentView?.addSubview(figure)
        panel.contentView?.addSubview(hand)
        hand.addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: hand))
        return panel
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ object: AnyObject? = nil, _ action: @escaping (PetStage) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            guard let self else { return }
            action(self)
            self.update()
            self.stir()
        }
        observers.append((center, token))
    }

    private static func id(_ screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    private var petScreen: NSScreen? {
        NSScreen.screens.first { Self.id($0) == home } ?? NSScreen.screens.first
    }

    private var ballScreen: NSScreen? {
        NSScreen.screens.first { Self.id($0) == court } ?? petScreen
    }

    private func layout() {
        guard let pet = petScreen, let toy = ballScreen else { return }
        home = Self.id(pet)
        court = Self.id(toy)
        physics.resize(bounds(pet))
        ball.resize(bounds(toy))
        arrange()
        stir()
    }

    private func arrange() {
        guard let window, let field, let pet = petScreen, let toy = ballScreen else { return }
        for (panel, up, screen) in [(window, raised, pet), (field, tossed, toy)] {
            panel.setFrame(up ? screen.frame : Self.strip(screen), display: false)
        }
        for figure in [view, ballView] as [NSView] { figure.frame = CGRect(x: figure.frame.minX, y: 0, width: Self.width, height: Self.height) }
        shelter()
        place()
        lift()
        if let bubble { show(bubble) }
    }

    private func bounds(_ screen: NSScreen) -> CGRect {
        let top = max(Self.height, screen.visibleFrame.maxY - screen.frame.minY)
        let left = neighbor(screen, -1) == nil ? 0 : Self.spill, right = neighbor(screen, 1) == nil ? 0 : Self.spill
        return CGRect(x: -left, y: Self.ground, width: screen.frame.width + left + right, height: top - Self.ground)
    }

    private func neighbor(_ screen: NSScreen, _ side: CGFloat) -> NSScreen? {
        let a = screen.frame
        return NSScreen.screens.filter {
            let b = $0.frame
            return !full.contains(Self.id($0)) && abs(side > 0 ? b.minX - a.maxX : a.minX - b.maxX) < 1 && b.minY <= a.minY + PetPhysics.hop && b.maxY >= a.minY + Self.height
        }.min { abs($0.frame.minY - a.minY) < abs($1.frame.minY - a.minY) }
    }

    private func cross() {
        var moved = false
        if let from = petScreen, let to = destination(from, physics.origin.x, physics.state == .held) {
            physics.move(by: Self.offset(from, to), to: bounds(to))
            home = Self.id(to)
            moved = true
        }
        if let from = ballScreen, let to = destination(from, ball.center.x, ball.held) {
            ball.move(by: Self.offset(from, to), to: bounds(to))
            court = Self.id(to)
            moved = true
        }
        if moved { arrange() }
    }

    private func destination(_ from: NSScreen, _ x: CGFloat, _ held: Bool) -> NSScreen? {
        guard held else { return x < 0 ? neighbor(from, -1) : x > from.frame.width ? neighbor(from, 1) : nil }
        let point = NSEvent.mouseLocation
        guard fake == nil, !from.frame.contains(point) else { return nil }
        return NSScreen.screens.first { $0.frame.contains(point) && !full.contains(Self.id($0)) }
    }

    private static func offset(_ from: NSScreen, _ to: NSScreen) -> CGVector {
        CGVector(dx: from.frame.minX - to.frame.minX, dy: from.frame.minY - to.frame.minY)
    }

    #if APPSTORE
    private static func fullscreen(_ screen: NSScreen, in windows: [[String: Any]]) -> Bool {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        return windows.contains { info in
            guard info[kCGWindowLayer as String] as? Int == 0, info[kCGWindowOwnerPID as String] as? Int != me,
                  info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return false }
            return bounds.equalTo(frame)
        }
    }
    #else
    private static let space: ((String) -> Int32)? = {
        typealias Connection = @convention(c) () -> Int32
        typealias Current = @convention(c) (Int32, CFString) -> UInt64
        typealias Kind = @convention(c) (Int32, UInt64) -> Int32
        func load<T>(_ names: String...) -> T? {
            names.lazy.compactMap { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) }.first.map { unsafeBitCast($0, to: T.self) }
        }
        guard let connection: Connection = load("SLSMainConnectionID", "CGSMainConnectionID"),
              let current: Current = load("SLSManagedDisplayGetCurrentSpace", "CGSManagedDisplayGetCurrentSpace"),
              let kind: Kind = load("SLSSpaceGetType", "CGSSpaceGetType") else { return nil }
        return { display in
            let cid = connection()
            return kind(cid, current(cid, display as CFString))
        }
    }()

    private static func fullscreen(_ screen: NSScreen, in _: [[String: Any]]) -> Bool {
        guard let space else { return false }
        if !NSScreen.screensHaveSeparateSpaces { return space("Main") == 4 }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id(screen))?.takeRetainedValue(), let name = CFUUIDCreateString(nil, uuid) else { return false }
        return space(name as String) == 4
    }
    #endif

    private static func covered(_ body: CGRect, on screen: NSScreen, in windows: [[String: Any]], whole: Bool = false) -> Bool {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let spot = CGRect(x: screen.frame.minX + body.minX, y: top - screen.frame.minY - body.maxY, width: body.width, height: body.height)
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        return windows.contains { info in
            guard info[kCGWindowLayer as String] as? Int == 0, info[kCGWindowOwnerPID as String] as? Int != me,
                  info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return false }
            return whole ? bounds.contains(spot) : bounds.contains(CGPoint(x: spot.midX, y: spot.midY))
        }
    }

    private static func obscured(_ panel: NSPanel?, _ body: CGRect, _ screen: NSScreen?, _ windows: [[String: Any]]) -> Bool {
        guard let panel, let screen, panel.isVisible, panel.level == level else { return false }
        return !panel.occlusionState.contains(.visible) || covered(body, on: screen, in: windows, whole: true)
    }

    private func onscreen() -> [[String: Any]] {
        snapshot ?? CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func strip(_ screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
    }

    private func shelter() {
        guard let pet = petScreen, let toy = ballScreen else { return }
        physics.roof = Self.height
        ball.roof = Self.height
        #if !APPSTORE
        let now = ProcessInfo.processInfo.systemUptime, current = NSScreen.screens.flatMap { [$0.frame, $0.visibleFrame] }
        if PetPace.dock(now, next: nextAsk, moved: current != frames) {
            docked = Self.tiles()
            nextAsk = now + PetPace.recheck
            frames = current
        }
        #endif
        physics.dock = Self.dock(pet, physics.dock, docked)
        ball.dock = Self.id(toy) == Self.id(pet) ? physics.dock : Self.dock(toy, ball.dock, docked)
    }

    private static func dock(_ screen: NSScreen, _ known: CGRect?, _ tiles: CGRect?) -> CGRect? {
        let top = screen.visibleFrame.minY - screen.frame.minY
        guard top > ground + PetPhysics.size.height else { return nil }
        #if APPSTORE
        return CGRect(x: 0, y: 0, width: screen.frame.width, height: top)
        #else
        guard let tiles else { return known ?? CGRect(x: 0, y: 0, width: screen.frame.width, height: top) }
        return CGRect(x: tiles.minX - screen.frame.minX - 8, y: 0, width: tiles.width + 16, height: top)
        #endif
    }

    #if !APPSTORE
    private static func tiles() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: AppConstants.dockBundleID).first else { return nil }
        let dock = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(dock, 0.25)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dock, kAXChildrenAttribute as CFString, &children) == .success, let children = children as? [AXUIElement] else { return nil }
        for child in children {
            AXUIElementSetMessagingTimeout(child, 0.25)
            var role: CFTypeRef?, position: CFTypeRef?, size: CFTypeRef?
            var point = CGPoint.zero, extent = CGSize.zero
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success, role as? String == kAXListRole,
                  AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size) == .success,
                  let position, CFGetTypeID(position) == AXValueGetTypeID(),
                  let size, CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
                  AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent),
                  extent.width > 0 else { continue }
            return CGRect(origin: point, size: extent)
        }
        return nil
    }
    #endif

    func update() {
        guard let window, let field else { return }
        let hidden = asleep || locked || fullscreen || hot || GameModeTool.shared.isPlaying
        let toy = PetTool.shared.ball && !physics.calm && !hidden
        let was = (window.isVisible, field.isVisible)
        if hidden {
            window.orderOut(nil)
            hideBubble()
        } else if !window.isVisible {
            window.orderFrontRegardless()
        }
        if toy != field.isVisible { toy ? field.orderFrontRegardless() : field.orderOut(nil) }
        if !toy, ball.held { drop() }
        if hidden || petCovered && (!toy || toyCovered) {
            drop()
            window.ignoresMouseEvents = true
            field.ignoresMouseEvents = true
        }
        pace(ProcessInfo.processInfo.systemUptime)
        if was != (window.isVisible, field.isVisible) { stir() }
    }

    func power() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        hot = [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        battery = Battery.read()?.phase == .onBattery
        update()
        stir()
    }

    private func checkFullscreen() {
        let windows = onscreen()
        func rects(_ layer: Int) -> [CGRect] {
            windows.compactMap { info -> CGRect? in
                guard info[kCGWindowLayer as String] as? Int == layer, info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: bounds)
            }
        }
        let covers = rects(0), bars = rects(Int(CGWindowLevelForKey(.mainMenuWindow)))
        let screens = NSScreen.screens
        let now = Set(screens.filter { screen in
            let display = CGDisplayBounds(Self.id(screen)), top = screen.safeAreaInsets.top
            let body = CGRect(x: display.minX, y: display.minY + top, width: display.width, height: display.height - top)
            return Self.fullscreen(screen, in: windows) || covers.contains { $0.contains(top > 0 ? body : display) } && !bars.contains { $0.intersects(display) }
        }.map(Self.id))
        var moved = now != full
        full = now
        if let free = screens.first(where: { !now.contains(Self.id($0)) }) {
            if now.contains(home), !physics.aloft, let from = petScreen {
                let x = physics.origin.x / from.frame.width * free.frame.width
                physics.move(by: CGVector(dx: x - physics.origin.x, dy: Self.ground - physics.origin.y), to: bounds(free))
                home = Self.id(free)
                moved = true
            }
            if now.contains(court), !now.contains(home), !ball.aloft, let from = ballScreen, let to = petScreen {
                let x = ball.center.x / from.frame.width * to.frame.width
                ball.move(by: CGVector(dx: x - ball.center.x, dy: Self.ground - ball.center.y), to: bounds(to))
                court = home
                moved = true
            }
        }
        if moved { layout() }
        fullscreen = !now.isEmpty
        let was = (petCovered, toyCovered)
        petCovered = Self.obscured(window, physics.frame, petScreen, windows)
        toyCovered = Self.obscured(field, ball.frame, ballScreen, windows)
        update()
        if was != (petCovered, toyCovered) { stir() }
    }

    private func reconcile() {
        guard let window, let field, let pet = petScreen, let toy = ballScreen else { return }
        asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        locked = GameModeTool.screenLocked
        guard !asleep, !locked else { return update() }
        snapshot = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        defer { snapshot = nil }
        let now = ProcessInfo.processInfo.systemUptime
        if let progress, window.isVisible, now >= ticked {
            ticked = now + 30
            progress.tick(now: Date())
        }
        physics.recover()
        if physics.aloft != raised || ball.aloft != tossed {
            rise()
        } else if [(window, raised, pet), (field, tossed, toy)].contains(where: { $0.frame != ($1 ? $2.frame : Self.strip($2)) }) {
            layout()
        }
        shelter()
        lift()
        checkFullscreen()
        let listed = Set(onscreen().compactMap { $0[kCGWindowNumber as String] as? Int })
        for panel in [window, field] where panel.isVisible && !listed.contains(panel.windowNumber) { panel.orderFrontRegardless() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        advance(link.timestamp)
    }

    private func advance(_ time: CFTimeInterval) {
        var dt = last.map { time - $0 } ?? 0
        last = time
        let now = ProcessInfo.processInfo.systemUptime
        if waited {
            physics.wait(dt)
            physics.resize(physics.bounds)
            ball.resize(ball.bounds)
            dt = 0
            waited = false
        }
        advanced = now
        play(demo)
        guard let pet = petScreen, let pitch = ballScreen else { return }
        let point = fake ?? pointer(pet, physics.state == .held, physics.frame, window), reach = fake ?? pointer(pitch, ball.held, ball.frame, field)
        if NSEvent.pressedMouseButtons & 1 == 0 { press = nil }
        physics.ledge = demo == "platform" ? demoLedge : selection(pet)
        ball.ledge = demo == "platform" ? demoLedge : selection(pitch)
        if lowPower {
            if physics.canSit { physics.doze() }
        } else if demo == nil, now >= felt + 0.25 {
            let on = PetTool.shared.rhythm
            let idle = on ? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput) : 0
            let typed = on ? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) : .infinity
            physics.sense(idle: idle, typed: typed, now - felt)
            if idle < 1 { dull = .random(in: 20...40) } else if idle >= dull || (typed >= 5 && now - touched >= 600) { feel(.bored, now) }
            felt = now
        }
        if petCovered, physics.grounded { physics.wait(dt) } else { physics.step(dt, cursor: point) }
        if now >= blinked + PetPace.blinks { blinked = now }
        let toy = field?.isVisible == true, together = Self.id(pet) == Self.id(pitch)
        if toy {
            if together, physics.kick(&ball) {
                progress?.add(.kicks)
                feel(.happy, now)
            }
            ball.step(dt, cursor: physics.state == .held ? nil : reach, body: physics.aloft || !together ? nil : (physics.previous, physics.frame))
            if ball.impact > 700, physics.grounded || physics.state == .jump { physics.bump(ball.frame) }
            if ball.nudged { chase = min(chase, now + 0.4) }
            if ball.nudged, !nudging { progress?.add(.plays) }
            nudging = ball.nudged
            if now >= chase {
                physics.face(ball.center.x + pitch.frame.minX - pet.frame.minX)
                chase = now + .random(in: 6...16)
            }
        }
        let events = physics.drain()
        if let progress {
            events.compactMap(\.counter).forEach { progress.add($0) }
            progress.walk(physics.walked)
        }
        if physics.state == .held || ball.held, fake == nil, NSEvent.pressedMouseButtons & 1 == 0 { drop() }
        cues(point, events, now)
        cross()
        rise()
        place()
        lift()
        let catchable = point.map(physics.touches) ?? false, reachable = toy && (reach.map(ball.touches) ?? false)
        if let window, window.ignoresMouseEvents == (catchable || physics.state == .held) { window.ignoresMouseEvents.toggle() }
        if let field, field.ignoresMouseEvents == (reachable || ball.held) { field.ignoresMouseEvents.toggle() }
        if phrase != nil, physics.state != .sit { hideBubble() }
        talk(ProcessInfo.processInfo.systemUptime)
        bake(now)
        pace(now)
    }

    private func gauge(_ now: Double) -> PetPace {
        var pace = PetPace()
        let toy = field?.isVisible == true
        pace.hidden = window?.isVisible != true
        pace.covered = petCovered && (!toy || toyCovered)
        pace.lowPower = lowPower
        pace.battery = battery
        pace.baked = view.looping
        if toy, !ball.resting { pace.flying = true }
        if petCovered {
            if !physics.grounded { pace.flying = true }
        } else {
            pace.watch(physics, still: lowPower, at: advanced)
            if view.pose.lid < 1 {
                pace.feel(feelings.mind.still(at: now))
                pace.blink(after: blinked, at: now)
            }
            if view.pose.twinkle != 0 { pace.moving = true }
        }
        if !lowPower {
            pace.expect(nextLook, after: advanced)
            if let eager { pace.expect(max(eager + 60, nextCheer), after: advanced) }
            if feelings.owed != nil { pace.expect(advanced + 1, after: advanced) }
            if physics.state == .doze, PetTool.shared.rhythm { pace.expect(felt + 1, after: advanced) }
        }
        if demo == nil, physics.state == .walk || physics.state == .rest { pace.expect(nextTalk, after: advanced) }
        pace.near = near(now)
        if press != nil || fake != nil || demo != nil { pace.moving = true }
        return pace
    }

    private func pace(_ now: Double) {
        guard let link else { return }
        let pace = gauge(now)
        switch pace.mode(at: now) {
        case .run(let minimum, let maximum, let preferred):
            let range = CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: preferred)
            if link.preferredFrameRateRange != range { link.preferredFrameRateRange = range }
            for timer in [peek, blind, alarm] { timer?.invalidate() }
            (peek, blind, alarm) = (nil, nil, nil)
            link.isPaused = false
        case .blind:
            link.isPaused = true
            for timer in [peek, alarm] { timer?.invalidate() }
            (peek, alarm) = (nil, nil)
            if blind == nil {
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.advance(CACurrentMediaTime()) }
                timer.tolerance = 0.05
                RunLoop.main.add(timer, forMode: .common)
                blind = timer
            }
        case .wait(let until, let slack):
            link.isPaused = true
            blind?.invalidate()
            blind = nil
            waited = true
            alarm?.invalidate()
            alarm = nil
            if until.isFinite {
                let timer = Timer(timeInterval: max(0, until - now), repeats: false) { [weak self] _ in self?.advance(CACurrentMediaTime()) }
                timer.tolerance = slack
                RunLoop.main.add(timer, forMode: .common)
                alarm = timer
            }
            if peek == nil { scout(now) }
        case .off:
            link.isPaused = true
            for timer in [blind, peek, alarm] { timer?.invalidate() }
            (blind, peek, alarm) = (nil, nil, nil)
            waited = true
            if pace.hidden { last = nil }
        }
    }

    func stir() {
        guard let link, window?.isVisible == true, link.isPaused else { return }
        alarm?.invalidate()
        alarm = nil
        peek?.invalidate()
        peek = nil
        link.isPaused = false
    }

    private func scout(_ now: Double) {
        let point = NSEvent.mouseLocation
        let timer = Timer(timeInterval: bodies.map { PetPace.glance(point, $0, still: hover.at < now) }.min() ?? 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.peek = nil
            let now = ProcessInfo.processInfo.systemUptime
            if self.near(now) { self.stir() } else { self.scout(now) }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        peek = timer
    }

    private var bodies: [CGRect] {
        var bodies: [CGRect] = []
        if !petCovered, let pet = petScreen { bodies.append(physics.frame.offsetBy(dx: pet.frame.minX, dy: pet.frame.minY)) }
        if field?.isVisible == true, !toyCovered, let toy = ballScreen { bodies.append(ball.frame.offsetBy(dx: toy.frame.minX, dy: toy.frame.minY)) }
        return bodies
    }

    private func near(_ now: Double) -> Bool {
        let point = NSEvent.mouseLocation
        if hypot(point.x - hover.point.x, point.y - hover.point.y) > 2 { hover = (point, now) }
        guard now - hover.at < PetPace.linger else { return false }
        return window?.ignoresMouseEvents == false || field?.ignoresMouseEvents == false || bodies.contains { PetPace.near(point, $0) }
    }

    private func bake(_ now: Double) {
        guard !view.looping, !petCovered, demo == nil, !lowPower, !physics.calm, physics.state == .doze, physics.clock >= 2.6 else { return }
        let outfit = PetProgress.shared.outfit
        let poses = (0..<130).map { i in
            var copy = physics
            copy.wait(Double(i) * 10.8 / 130)
            var pose = PetPose(copy, scale: Self.scale, time: now, blink: false)
            pose.outfit = outfit
            return pose
        }
        view.loop(poses, over: 10.8)
        baked = poses[0]
    }

    private static func same(_ a: PetPose, _ b: PetPose) -> Bool {
        var a = a
        a.squash = b.squash
        a.nap = b.nap
        return a == b
    }

    private func attune() {
        feelings.progress = progress
        feelings.muted = demo != nil || petCovered
    }

    @discardableResult
    private func feel(_ mood: PetMood, _ now: TimeInterval) -> Bool {
        attune()
        return feelings.feel(mood, now, &physics)
    }

    private func cues(_ point: CGPoint?, _ events: [PetPhysics.Event], _ now: TimeInterval) {
        guard demo == nil else { return }
        attune()
        feelings.cue(events, now, Date(), &physics)
        if physics.state == .held {
            still = point
            stillAt = now
            if hypot(physics.vx, physics.vy) >= 300 { cradled = now } else if now - cradled >= 1.2 { feel(.happy, now) }
        } else if let point, let spot = still, hypot(point.x - spot.x, point.y - spot.y) < 3 {
            let rested = now - stillAt, frame = physics.frame, ahead = physics.facing > 0 ? point.x - frame.maxX : frame.minX - point.x
            if physics.touches(point) {
                touched = now
                if rested >= 1.2 { feel(.shy, now) }
            } else if rested >= 0.8, ahead > 0, ahead < 80, abs(point.y - frame.midY) < 80 {
                feelings.mind.gaze = CGVector(dx: 1, dy: (frame.midY - point.y) / 80)
                feel(.curious, now)
            }
        } else {
            still = point
            stillAt = now
        }
        if physics.zest > 0.8 { eager = eager ?? now } else { eager = nil }
        if let eager, now - eager >= 60, now >= nextCheer, feel(.happy, now) { nextCheer = now + 600 }
        if now >= nextLook {
            nextLook = now + 60
            let idle = PetTool.shared.rhythm ? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput) : 0
            if idle >= dull, !(5..<23).contains(Calendar.current.component(.hour, from: Date())) || Battery.read().map({ $0.phase == .onBattery && $0.charge <= 10 }) == true { feel(.sleepy, now) }
        }
        if feelings.owed != nil {
            let free = PetTool.shared.talks && !behindDock && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) >= 5 && !hearing(now)
            if let phrase = feelings.speak(now, &physics, free: free) { present(phrase) }
        }
    }

    private func pointer(_ screen: NSScreen, _ held: Bool, _ body: CGRect, _ panel: NSPanel?) -> CGPoint? {
        let point = NSEvent.mouseLocation
        guard held || screen.frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        guard !held, let panel, PetPace.near(local, body) else { return local }
        let now = ProcessInfo.processInfo.systemUptime
        if probe.map({ PetPace.ask(point, now, after: ($0.point, $0.time)) }) ?? true {
            let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0), ours = [window, field, bubble].contains { $0?.windowNumber == number }
            let info = number > 0 && !ours ? (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]])?.first : nil
            probe = (point, now, info?[kCGWindowLayer as String] as? Int)
        }
        return probe?.layer.map { $0 > panel.level.rawValue } == true ? nil : local
    }

    private func selection(_ screen: NSScreen) -> CGRect? {
        guard let press else { return nil }
        guard NSPasteboard(name: .drag).changeCount == drags else {
            self.press = nil
            return nil
        }
        let point = NSEvent.mouseLocation
        let rect = CGRect(x: min(press.x, point.x), y: min(press.y, point.y), width: abs(point.x - press.x), height: abs(point.y - press.y))
        return rect.width > 4 && rect.height > 4 ? rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) : nil
    }

    private var demoLedge: CGRect? {
        ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 14) < 9 ? CGRect(x: physics.bounds.width * 0.2, y: 0, width: 220, height: 34) : nil
    }

    private func pressed(_ point: CGPoint) {
        defer { stir() }
        guard window?.isVisible == true, let screen = NSScreen.screens.first else { return press = nil }
        if let pet = petScreen, let dock = physics.dock, dock.contains(CGPoint(x: point.x - pet.frame.minX, y: point.y - pet.frame.minY)) { return press = nil }
        let spot = CGPoint(x: point.x, y: screen.frame.maxY - point.y)
        let ours = [window, field, bubble].compactMap { $0?.windowNumber }
        drags = NSPasteboard(name: .drag).changeCount
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        let list = number > 0 && !ours.contains(number) ? CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]] ?? [] : []
        let windows = list.compactMap { info -> (layer: Int, frame: CGRect)? in
            guard info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (info[kCGWindowLayer as String] as? Int ?? 0, rect)
        }
        press = PetPhysics.desktop(spot, windows, displays: NSScreen.screens.map { CGDisplayBounds(Self.id($0)) }) ? point : nil
    }

    private func place() {
        let now = ProcessInfo.processInfo.systemUptime
        if !petCovered {
            put(view, physics.origin.x)
            var pose = PetPose(physics, scale: Self.scale, time: now, blink: now < blinked + PetPace.shut, still: lowPower)
            pose.outfit = PetProgress.shared.outfit
            pose.face = feelings.mind.face(at: now)
            pose.twinkle = pose.face.glow > 0 && !physics.calm && !lowPower ? now : 0
            if pose.lid >= 1 {
                pose.face = PetFace()
                pose.twinkle = 0
            }
            if !view.looping || !Self.same(pose, baked) { view.pose = pose }
            if grip.frame != physics.frame { grip.frame = physics.frame }
        }
        if field?.isVisible == true, !toyCovered {
            put(ballView, ball.center.x)
            ballView.pose = BallPose(ball, scale: Self.scale)
            if ballGrip.frame != ball.frame { ballGrip.frame = ball.frame }
        }
    }

    private func put<Pose>(_ figure: FigureView<Pose>, _ x: CGFloat) {
        let scale = window?.backingScaleFactor ?? 2
        let left = x - Self.width / 2, snapped = (left * scale).rounded(.down) / scale
        if figure.frame.minX != snapped { figure.setFrameOrigin(CGPoint(x: snapped, y: 0)) }
        figure.shift = left - snapped
    }

    private func lift() {
        guard let window, let field else { return }
        for (panel, up, buried, body, floor, dock, screen) in [(window, raised, hiddenUp, physics.frame, physics.bounds.minY, physics.dock, petScreen), (field, tossed, hiddenToss, ball.frame, ball.bounds.minY, ball.dock, ballScreen)] {
            var level = up && !buried ? .statusBar : body.minY > floor + 0.5 && body.maxY > (dock?.maxY ?? floor) ? Self.front : Self.level
            let number = panel.windowNumber
            if level != Self.front {
                sunk.remove(number)
            } else if panel.level == Self.level, !sunk.contains(number), let screen, fullscreen || Self.covered(CGRect(origin: CGPoint(x: body.minX, y: floor), size: body.size), on: screen, in: onscreen()) {
                sunk.insert(number)
            }
            if sunk.contains(number) { level = Self.level }
            if panel.level != level { panel.level = level }
        }
        if let bubble, bubble.level != window.level { bubble.level = window.level }
    }

    private static var front: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    }

    private func rise() {
        guard physics.aloft != raised || ball.aloft != tossed else { return }
        if physics.aloft, !raised, let pet = petScreen { hiddenUp = Self.covered(physics.frame, on: pet, in: onscreen()) }
        if ball.aloft, !tossed, let toy = ballScreen { hiddenToss = Self.covered(ball.frame, on: toy, in: onscreen()) }
        raised = physics.aloft
        tossed = ball.aloft
        layout()
    }

    private func play(_ demo: String?) {
        switch demo {
        case "jump" where physics.state == .walk && physics.clock > 0.8:
            physics.jump()
        case "doze" where physics.state == .walk && physics.clock > 1.5:
            physics.doze()
        case "doze" where physics.state == .doze && physics.clock > 8:
            physics.wake()
        case "typing":
            physics.sense(idle: 0, typed: 0, 1.0 / 30)
        case "moods" where Int(ProcessInfo.processInfo.systemUptime / 4) != shown:
            let now = ProcessInfo.processInfo.systemUptime
            shown = Int(now / 4)
            feelings.mind = PetMind()
            feelings.mind.feel(PetMood.allCases[1 + shown % 9], at: now)
        case "tumble" where physics.state == .walk && physics.clock > 1.2:
            physics.bump(physics.frame.offsetBy(dx: physics.facing * 20, dy: 0))
        case "sit" where phrase == nil, "update" where phrase == nil:
            let version = Version.parts(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            let next = "\(version.first ?? 1).\(version.dropFirst().first.map { $0 + 1 } ?? 1).0"
            say(demo == "sit" ? PetPhrases.all[0] : PetPhrases.update(next), for: .infinity)
        case "hold" where physics.state == .walk && physics.clock > 1.5, "throw" where physics.state == .walk && physics.clock > 1.5:
            fake = CGPoint(x: physics.origin.x, y: physics.frame.maxY - PetPhysics.scruff)
            anchor = fake ?? .zero
            grab(at: anchor, in: window)
        case "hold" where physics.state == .held, "throw" where physics.state == .held:
            let t = physics.clock
            fake = CGPoint(x: anchor.x + 80 * sin(t * 3), y: anchor.y + 300 * min(t, 1))
            if demo == "throw", t > 2.1 {
                fake = nil
                drop()
            }
        case "ball" where ball.resting && physics.state == .walk && physics.clock > 2:
            ball.kick(CGVector(dx: physics.origin.x > ball.center.x ? 420 : -420, dy: 260))
        case "carry" where ball.resting && physics.state == .walk && physics.clock > 2:
            fake = ball.center
            anchor = ball.center
            grabbed = ProcessInfo.processInfo.systemUptime
            grab(at: anchor, in: field)
        case "carry" where ball.held:
            let t = ProcessInfo.processInfo.systemUptime - grabbed
            fake = CGPoint(x: anchor.x + 80 * sin(t * 3), y: anchor.y + 300 * min(t, 1))
            if t > 2.1 {
                fake = nil
                drop()
            }
        default:
            break
        }
    }

    private func talk(_ now: TimeInterval) {
        if let progress, progress.hasNews {
            if PetTool.shared.talks { nextTalk = min(nextTalk, now + 3) } else { progress.hush() }
        }
        guard now >= nextTalk, physics.state == .walk || physics.state == .rest, demo == nil else { return }
        guard PetTool.shared.talks else { return nextTalk = now + .random(in: 1200...1800) }
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 5
        if typing || physics.zest < -0.2 || GameModeTool.shared.isPlaying || hearing(now) { return nextTalk = now + 45 }
        guard !behindDock else { return }
        say(nextPhrase(), for: 4.4)
        nextTalk = now + .random(in: 1200...1800)
    }

    private var behindDock: Bool {
        guard let screen = petScreen, screen.visibleFrame.minY > screen.frame.minY else { return false }
        let x = physics.origin.x / screen.frame.width
        return x > 0.18 && x < 0.82
    }

    private func nextPhrase() -> PetPhrase {
        if let award = progress?.news.first { return PetPhrases.award(award) }
        #if !APPSTORE
        let state = MainActor.assumeIsolated { Updater.shared.state }
        if !dev, case .available(let version) = state, UserDefaults.standard.string(forKey: "pet-told-update") != version {
            UserDefaults.standard.set(version, forKey: "pet-told-update")
            return PetPhrases.update(version)
        }
        #endif
        if deck.isEmpty { deck = PetPhrases.all.filter { $0.id != "space" || PetTool.shared.listening }.shuffled() }
        return deck.removeLast()
    }

    private func hearing(_ now: Double) -> Bool {
        if now - heard.at >= 1 { heard = (now, Self.microphoneInUse) }
        return heard.on
    }

    private static var microphoneInUse: Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private func say(_ phrase: PetPhrase, for seconds: Double) {
        guard physics.sit(seconds) else { return }
        present(phrase)
    }

    private func present(_ phrase: PetPhrase) {
        hideBubble()
        let clickable = phrase.id == "update" || phrase.id == "award" || phrase.link != nil
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.level = Self.level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = !clickable
        panel.contentView = BubbleHost(rootView: PetBubble(text: phrase.text, clickable: clickable, tail: 0) { [weak self] in self?.open(phrase) })
        panel.alphaValue = 0
        bubble = panel
        self.phrase = phrase
        show(panel)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        if phrase.id == "award" { progress?.popNews() } else { progress?.add(.phrases) }
    }

    private func show(_ panel: NSPanel) {
        guard let window, let host = panel.contentView as? BubbleHost else { return }
        let size = host.fittingSize
        let pet = window.frame.minX + physics.origin.x
        let screen = window.frame
        let x = min(max(pet - size.width / 2, screen.minX + 4), screen.maxX - size.width - 4)
        let tail = min(max(pet - x - size.width / 2, -size.width / 2 + 26), size.width / 2 - 26)
        if host.rootView.tail != tail { host.rootView.tail = tail }
        let frame = CGRect(x: x, y: screen.minY + physics.frame.maxY - 4, width: size.width, height: size.height).integral
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func hideBubble() {
        guard let panel = bubble else { return }
        bubble = nil
        phrase = nil
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 0 } completionHandler: { panel.orderOut(nil) }
    }

    private func open(_ phrase: PetPhrase) {
        if phrase.id == "update" {
            SettingsWindow.show(.about)
        } else if phrase.id == "award" {
            SettingsWindow.show(.pet)
        } else if let link = phrase.link {
            NSWorkspace.shared.open(link)
        }
        hideBubble()
    }
}

private extension PetPhysics.Event {
    var counter: PetCounter? {
        switch self {
        case .jump: .jumps
        case .leap: .leaps
        case .climb: .climbs
        case .tumble: .tumbles
        case .fling: .flights
        case .woke: nil
        }
    }
}
