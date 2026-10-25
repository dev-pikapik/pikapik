import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

@Observable
final class QuitOnCloseTool: Tool {
    let id = ToolID.quitOnClose
    let icon = Symbol.xmarkApp
    var title: String { SettingTitle.quitOnClose }
    var needs: [Permission] { [.accessibility, .inputMonitoring] }
    let tab = SettingsTab.windows

    private static let excludedKey = PreferenceKey.quitOnCloseExcluded
    fileprivate static let alwaysExcluded: Set<String> = [AppConstants.finderBundleID, Bundle.main.bundleIdentifier ?? ""]

    private(set) var isActive = false

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: id)
            refresh()
        }
    }

    var excluded: [String] {
        didSet { UserDefaults.standard.set(excluded, forKey: Self.excludedKey) }
    }

    @ObservationIgnored fileprivate var observers: [pid_t: AXObserver] = [:]
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var tapSource: CFRunLoopSource?
    /// An Accessibility question to another app can wait for seconds while that app is busy, and every pikapik tap runs on
    /// the main thread. So the observers are made, signed up and told the window news on a thread of their own, and the
    /// clicks and minimized windows are checked on a queue, where a busy app never freezes the keyboard or the mouse.
    @ObservationIgnored private var observing: RunLoopThread?
    @ObservationIgnored fileprivate let checks = DispatchQueue(label: "pikapik.quit-on-close", qos: .userInitiated)

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: id)
        excluded = UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? []
    }

    func load() {
        excluded = UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? []
        isEnabled = UserDefaults.standard.bool(forKey: id)
    }

    var settingsView: AnyView {
        AnyView(QuitOnCloseSettings(tool: self))
    }

    var isDefault: Bool { !isEnabled && excluded.isEmpty }

    func reset() {
        isEnabled = false
        excluded = []
    }

    func refresh() {
        stop()
        guard isEnabled, MainCopy.canAct, AXIsProcessTrusted(), Permissions.shared.inputMonitoring else { return }
        if observing == nil { observing = RunLoopThread(name: "pikapik.quit-on-close") }
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self?.isActive == true { self?.watch(app) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.unwatch(app.processIdentifier)
            },
        ]
        NSWorkspace.shared.runningApplications.forEach(watch)
        startTap()
        isActive = true
    }

    private func stop() {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens = []
        observing?.run { [self] in observers.keys.forEach(stopObserving) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        tap = nil
        tapSource = nil
        isActive = false
    }

    private func startTap() {
        let types: [CGEventType] = [.leftMouseDown, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: quitOnCloseTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Runs on the checks queue. Only a click in a title bar corner is looked at, and only in the app it belongs to.
    fileprivate func clicked(at point: CGPoint) {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let pid = TitleBarCorner.owner(at: point, in: windows) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success, let element else { return }
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard Self.string(element, kAXSubroleAttribute) == kAXCloseButtonSubrole as String else { return }
        DispatchQueue.main.async { [weak self] in self?.scheduleChecks(pid) }
    }

    fileprivate func closeShortcutPressed() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        scheduleChecks(pid)
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !app.isTerminated, app.activationPolicy == .regular,
              !Self.alwaysExcluded.contains(app.bundleIdentifier ?? "") else { return }
        observing?.run { [self] in observe(pid) }
    }

    private func unwatch(_ pid: pid_t) {
        observing?.run { [self] in stopObserving(pid) }
    }

    /// Runs on the observing thread, like everything that touches `observers`.
    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, quitOnCloseCallback, &observer) == .success, let observer else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXMainWindowChangedNotification as CFString, refcon)
        Self.windows(of: element)?.forEach { track($0, observer: observer) }
    }

    /// Runs on the observing thread.
    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// Runs on the observing thread.
    fileprivate func track(_ window: AXUIElement, observer: AXObserver) {
        AXUIElementSetMessagingTimeout(window, 0.5)
        guard Self.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return }
        AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Runs on the observing thread.
    fileprivate func windowClosed(observer: AXObserver) {
        guard let pid = observers.first(where: { $0.value === observer })?.key else { return }
        DispatchQueue.main.async { [weak self] in self?.scheduleChecks(pid) }
    }

    private func scheduleChecks(_ pid: pid_t) {
        for delay in [0.35, 1.0, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.whenWindowless(pid) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.whenWindowless(pid) { $0.terminate() }
                    }
                }
            }
        }
    }

    /// Calls `then` on the main thread when the app may quit and has no window left. The windows in the Dock are counted on
    /// the checks queue, because that asks the app.
    private func whenWindowless(_ pid: pid_t, then: @escaping (NSRunningApplication) -> Void) {
        guard mayQuit(pid) != nil else { return }
        checks.async { [weak self] in
            guard !Self.mayHaveMinimizedWindow(pid) else { return }
            DispatchQueue.main.async {
                if let app = self?.mayQuit(pid) { then(app) }
            }
        }
    }

    private func mayQuit(_ pid: pid_t) -> NSRunningApplication? {
        guard isEnabled, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, !app.isHidden,
              app.activationPolicy == .regular,
              !Self.alwaysExcluded.contains(app.bundleIdentifier ?? ""),
              !excluded.contains(app.bundleIdentifier ?? ""),
              !GameModeTool.shared.keepsOpen(app),
              !Self.hasLiveCGWindow(pid)
        else { return nil }
        return app
    }

    /// The app's windows, or nil when it did not answer in time.
    private static func windows(of app: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) {
        case .success:
            let windows = value as? [AXUIElement] ?? []
            windows.forEach { AXUIElementSetMessagingTimeout($0, 0.5) }
            return windows
        case .cannotComplete:
            return nil
        default:
            return []
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// True when the app has a window in the Dock, or is too busy to say, so a busy app is never quit by mistake.
    private static func mayHaveMinimizedWindow(_ pid: pid_t) -> Bool {
        guard let windows = windows(of: AXUIElementCreateApplication(pid)) else { return true }
        return windows.contains { window in
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
            return result == .cannotComplete || result == .success && value as? Bool == true
        }
    }

    private static func hasLiveCGWindow(_ pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = list.filter { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) >= 80, (bounds["Height"] ?? 0) >= 80
            else { return false }
            return true
        }
        if candidates.contains(where: { $0[kCGWindowIsOnscreen as String] as? Bool == true }) { return true }
        #if APPSTORE
        return !candidates.isEmpty
        #else
        let visible = visibleSpaces()
        return candidates.contains { info in
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, [id] as CFArray)?.takeRetainedValue() as? [NSNumber]
            else { return false }
            return !spaces.isEmpty && spaces.allSatisfy { !visible.contains($0.intValue) }
        }
        #endif
    }

    #if !APPSTORE
    private static func visibleSpaces() -> Set<Int> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] ?? []
        return Set(displays.compactMap { display in
            let current = display["Current Space"] as? [String: Any]
            return (current?["ManagedSpaceID"] as? Int) ?? (current?["id64"] as? Int)
        })
    }
    #endif
}

#if !APPSTORE
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?
#endif

private func quitOnCloseCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tool = Unmanaged<QuitOnCloseTool>.fromOpaque(refcon).takeUnretainedValue()
    if notification as String == kAXWindowCreatedNotification {
        tool.track(element, observer: observer)
    } else {
        tool.windowClosed(observer: observer)
    }
}

private func quitOnCloseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tool = Unmanaged<QuitOnCloseTool>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tool.reenableTap()
    case .leftMouseDown:
        let point = event.location
        tool.checks.async { tool.clicked(at: point) }
    case .keyDown:
        let flags = event.flags
        if flags.contains(.maskCommand), flags.isDisjoint(with: [.maskControl, .maskAlternate]),
           event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_W {
            DispatchQueue.main.async { tool.closeShortcutPressed() }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

struct QuitOnCloseArt: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let durations = [1.3, 1.15, 0.15, 1.9]

    var body: some View {
        IllustrationRow(loop: Self.durations) { tick in
            let step = reduceMotion ? 3 : tick % Self.durations.count
            let closed = step == 3
            Stage {
                ArtWindow {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach([54, 38, 46], id: \.self) { Capsule().fill(Color.primary.opacity(0.12)).frame(width: CGFloat($0), height: 4) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                }
                .scaleEffect(closed ? 0.9 : 1)
                .opacity(closed ? (reduceMotion ? 0.4 : 0) : 1)
                .position(x: 150, y: 44)
                ArtDock(appDot: !(on && closed))
                    .position(x: 150, y: 102)
                if step >= 2 {
                    ArtRipple()
                        .position(x: 106, y: 19)
                }
                ArtCursor(pressed: step == 2)
                    .cursor(at: step == 0 ? CGPoint(x: 196, y: 56) : CGPoint(x: 104, y: 17))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: step)
        }
    }
}

private struct QuitOnCloseSettings: View {
    @Bindable var tool: QuitOnCloseTool
    @Environment(\.inSettings) private var inSettings

    var body: some View {
        if inSettings { QuitOnCloseArt(on: tool.isEnabled) }
        ToggleRow(
            icon: tool.icon,
            title: tool.title,
            subtitle: Text("Closing the last window quits the app"),
            hint: Text("Finder always stays open"),
            help: Text("Closing an app’s last window quits the app. Finder stays open."),
            isOn: $tool.isEnabled
        )
        AppExclusions(
            title: String(localized: "Never quit these apps"),
            apps: $tool.excluded,
            isEnabled: tool.isEnabled,
            skipped: QuitOnCloseTool.alwaysExcluded
        )
    }
}
