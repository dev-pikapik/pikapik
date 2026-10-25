import AppKit
import Carbon
import IOKit.pwr_mgt
import SwiftUI

@Observable
final class GameModeTool: Tool {
    static let shared = GameModeTool()

    let id = ToolID.gameMode
    let icon = Symbol.gamecontroller
    var title: String { SettingTitle.gameMode }
    let tab = SettingsTab.games

    private static let gamesKey = PreferenceKey.gameModeGames
    private static let notGamesKey = PreferenceKey.gameModeNotGames
    private static let systemShortcutsKey = PreferenceKey.gameModeSystemShortcuts
    private static let frameRateKey = PreferenceKey.gameModeFrameRate
    private static let frameRateCornerKey = PreferenceKey.gameModeFrameRateCorner
    private static let frameRateRecordingKey = PreferenceKey.gameModeFrameRateRecording
    private static let applicationsFolder = URL(fileURLWithPath: SystemPath.applications)
    private static let systemApplicationsFolder = URL(fileURLWithPath: SystemPath.systemApplications)
    private static let steamLibrarySubpath = "Library/Application Support/Steam/steamapps/common"

    private(set) var isActive = false
    private(set) var game: NSRunningApplication?
    private(set) var suggestions: [String] = []
    var isPlaying: Bool { game != nil }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: id)
            refresh()
        }
    }

    var rules: Set<GameRule> {
        didSet {
            GameRule.allCases.filter { rules.contains($0) != oldValue.contains($0) }
                .forEach { UserDefaults.standard.set(rules.contains($0), forKey: $0.key) }
            leave()
            update()
        }
    }

    var games: [String] {
        didSet {
            UserDefaults.standard.set(games, forKey: Self.gamesKey)
            suggestions.removeAll { GameRules.isAdded($0, in: games) }
            update()
        }
    }

    var notGames: [String] {
        didSet {
            UserDefaults.standard.set(notGames, forKey: Self.notGamesKey)
            suggestions.removeAll(where: notGames.contains)
        }
    }

    var systemShortcuts: [String] {
        didSet {
            UserDefaults.standard.set(systemShortcuts, forKey: Self.systemShortcutsKey)
            leave()
            update()
        }
    }

    var showsFrameRate: Bool {
        didSet {
            UserDefaults.standard.set(showsFrameRate, forKey: Self.frameRateKey)
            syncFrameRate()
        }
    }

    var frameRateCorner: FrameRateCorner {
        didSet {
            UserDefaults.standard.set(frameRateCorner.rawValue, forKey: Self.frameRateCornerKey)
            syncFrameRate()
        }
    }

    var needsRecording: Bool {
        didSet { UserDefaults.standard.set(needsRecording, forKey: Self.frameRateRecordingKey) }
    }

    func setSystemShortcut(_ id: Int32, mode: GameShortcutMode) {
        systemShortcuts = systemShortcuts.filter { $0.split(separator: ":").first != Substring(String(id)) }
            + (mode == .automatic ? [] : ["\(id):\(mode.rawValue)"])
    }

    @ObservationIgnored fileprivate var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored fileprivate var combos: Set<UInt64> = []
    @ObservationIgnored private var hinted = false
    @ObservationIgnored private var fence: CursorFence?
    @ObservationIgnored private var fenceTimer: Timer?
    @ObservationIgnored private var swipes: (blocksAll: Bool, except: Set<Int64>, corners: Set<Int>) = (false, [], [])
    #if !APPSTORE
    @ObservationIgnored private var cursorHeld = false
    #endif
    @ObservationIgnored private var assertion: IOPMAssertionID?
    @ObservationIgnored private let trace = HotKeyTrace()
    @ObservationIgnored fileprivate var languageBindings: [UInt64: (direction: InputSwitchGesture.Direction, automatic: Bool)] = [:]
    @ObservationIgnored fileprivate var inputIntent = GameInputIntent()
    @ObservationIgnored fileprivate var swallowed = SwallowedKeys()
    @ObservationIgnored fileprivate var allowedAppShortcuts: Set<UInt64> = []

    func allowsLanguageGesture(flags: CGEventFlags, at time: UInt64) -> Bool {
        inputIntent.allowsGesture(flags: flags, at: time)
    }

    private init() {
        let defaults = UserDefaults.standard
        GameRules.migrateControl(defaults)
        GameRules.migrateGroups(defaults)
        isEnabled = defaults.bool(forKey: ToolID.gameMode)
        rules = Self.savedRules
        games = defaults.stringArray(forKey: Self.gamesKey) ?? []
        notGames = defaults.stringArray(forKey: Self.notGamesKey) ?? []
        systemShortcuts = defaults.stringArray(forKey: Self.systemShortcutsKey) ?? []
        showsFrameRate = defaults.bool(forKey: Self.frameRateKey)
        frameRateCorner = Self.savedCorner
        needsRecording = defaults.bool(forKey: Self.frameRateRecordingKey)

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in GameModeTool.shared.update() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in GameModeTool.shared.leave() }
        }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDistributedCenter(), observer, gameModeNotification, name as CFString, nil, .deliverImmediately
            )
        }
    }

    func load() {
        let defaults = UserDefaults.standard
        rules = Self.savedRules
        games = defaults.stringArray(forKey: Self.gamesKey) ?? []
        notGames = defaults.stringArray(forKey: Self.notGamesKey) ?? []
        systemShortcuts = defaults.stringArray(forKey: Self.systemShortcutsKey) ?? []
        showsFrameRate = defaults.bool(forKey: Self.frameRateKey)
        frameRateCorner = Self.savedCorner
        isEnabled = defaults.bool(forKey: id)
        if game == nil { DockEdges.restore() }
    }

    var isDefault: Bool {
        !isEnabled && rules.count == GameRule.allCases.count && games.isEmpty && notGames.isEmpty && systemShortcuts.isEmpty
            && !showsFrameRate && frameRateCorner == .standard
    }

    func reset() {
        isEnabled = false
        rules = Set(GameRule.allCases)
        games = []
        notGames = []
        systemShortcuts = []
        showsFrameRate = false
        frameRateCorner = .standard
    }

    var settingsView: AnyView {
        AnyView(GameModeSettings(tool: self))
    }

    func refresh() {
        leave()
        stopTap()
        if isEnabled, MainCopy.canAct, AXIsProcessTrusted() { startTap() }
        update()
    }

    func confirm(_ key: String) {
        if !games.contains(key) { games.append(key) }
    }

    func add(_ url: URL) {
        Self.key(url).map(confirm)
    }

    static func choose() -> [URL] {
        let panel = NSOpenPanel()
        panel.directoryURL = applicationsFolder
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        NSApp.bringForward()
        return panel.runModal() == .OK ? panel.urls.filter { key($0) != nil } : []
    }

    func dismiss(_ key: String) {
        if !notGames.contains(key) { notGames.append(key) }
    }

    func keepsOpen(_ app: NSRunningApplication) -> Bool {
        games.contains(Self.key(app)) || isGame(app) || GameRules.launchers.contains(app.bundleIdentifier ?? "")
            || Self.looksLikeGame(app.bundleIdentifier, app.bundleURL ?? app.executableURL)
    }

    func refreshSuggestions() {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let folders = [
            Self.applicationsFolder, Self.systemApplicationsFolder,
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent(Self.steamLibrarySubpath),
        ]
        let contents = { (url: URL) in (try? files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] }
        let bundles = folders.flatMap(contents).flatMap { $0.pathExtension == "app" ? [$0] : contents($0).filter { $0.pathExtension == "app" } }
        let installed = bundles.compactMap { url -> String? in
            let id = Bundle(url: url)?.bundleIdentifier
            return Self.looksLikeGame(id, url) || id == "com.mojang.minecraftlauncher" ? id : nil
        }
        let running = AppShelf.windowed
            .filter { Self.looksLikeGame($0.bundleIdentifier, $0.bundleURL ?? $0.executableURL)
                || GameRules.minecraft($0.executableURL?.path ?? "") != nil }
            .map(Self.key)
        var seen = Set(notGames + [""])
        suggestions = (running + installed).filter { !GameRules.isAdded($0, in: games) && seen.insert($0).inserted }
    }

    fileprivate func update() {
        let app = NSWorkspace.shared.frontmostApplication
        if let app {
            let upgraded = GameRules.upgraded(games, id: app.bundleIdentifier, name: app.localizedName, path: app.executableURL?.path ?? "")
            if upgraded != games { return games = upgraded }
        }
        guard isEnabled, MainCopy.canAct, let app, isGame(app), !Self.screenLocked else {
            if game != nil { leave() }
            return
        }
        guard app.processIdentifier != game?.processIdentifier else { return }
        leave()
        enter(app)
    }

    private func enter(_ app: NSRunningApplication) {
        game = app
        let catalog = SystemShortcutCatalog.load()
        trace.disable(SystemShortcutCatalog.selected(catalog, rules: rules, values: systemShortcuts, appSwitcher: tap != nil))
        languageBindings = tap == nil ? [:] : SystemShortcutCatalog.languageBindings(catalog, rules: rules, values: systemShortcuts, disabled: Set(HotKeyTrace.ids(trace.defaults) ?? []))
        let choices = SystemGameShortcut.overrides(systemShortcuts)
        allowedAppShortcuts = Set(catalog.filter { $0.assigned && $0.mode(rules: rules, overrides: choices) == .system }.map { GameRules.combo(key: Int64($0.key), flags: $0.modifiers) })
        inputIntent = GameInputIntent(held: Set((0..<128).filter { ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains($0) && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }.map(Int64.init)))
        let pointerIDs = Set(catalog.filter { $0.pointer != nil }.map(\.id))
        combos = Set(
            (HotKeyTrace.ids(trace.defaults) ?? []).filter { !pointerIDs.contains($0) }.compactMap(SymbolicHotKeys.value)
                .filter { !GameRules.isGameInput($0.modifiers) && languageBindings[GameRules.combo(key: Int64($0.key), flags: $0.modifiers)] == nil }.map { GameRules.combo(key: Int64($0.key), flags: $0.modifiers) }
        )
        hinted = false
        let paused = PointerShortcuts.paused(catalog, rules: rules, values: systemShortcuts)
        swipes = (paused.blocksAll, paused.except, Set(PointerShortcuts.sides.indices).subtracting(paused.corners))
        #if APPSTORE
        if paused.blocksAll || !paused.except.isEmpty { moveFence() }
        DockEdges.calm(corners: paused.corners, hidesDock: false)
        #else
        let holdsCursor = rules.contains(.cursor)
        if holdsCursor || paused.blocksAll || !paused.except.isEmpty { moveFence() }
        DockEdges.calm(corners: paused.corners, hidesDock: holdsCursor)
        if holdsCursor {
            fenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in GameModeTool.shared.moveFence() }
        }
        #endif
        if rules.contains(.display) {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "pikapik Game Mode" as CFString, &id
            )
            if result == kIOReturnSuccess { assertion = id }
        }
        refreshCommandKeys()
        syncFrameRate()
    }

    func leave() {
        fenceTimer?.invalidate()
        fenceTimer = nil
        #if !APPSTORE
        if cursorHeld { _ = CursorLock.hold(nil) }
        cursorHeld = false
        #endif
        fence?.stop()
        fence = nil
        swipes = (false, [], [])
        DockEdges.restoreSoon()
        combos = []
        languageBindings = [:]
        inputIntent = GameInputIntent()
        allowedAppShortcuts = []
        if let assertion { IOPMAssertionRelease(assertion) }
        assertion = nil
        trace.restore()
        guard game != nil else { return }
        game = nil
        syncFrameRate()
        refreshCommandKeys()
    }

    private func syncFrameRate() {
        if showsFrameRate, let game {
            FrameRateMeter.shared.show(game.processIdentifier, corner: frameRateCorner)
        } else {
            FrameRateMeter.shared.hide()
        }
    }

    func hint() {
        guard isPlaying, !hinted else { return }
        hinted = true
        DispatchQueue.main.async { GameHint.show() }
    }

    func received(_ name: String) {
        #if APPSTORE
        Self.locked = name == "com.apple.screenIsLocked"
        #endif
        if name == "com.apple.screenIsLocked" {
            leave()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.update() }
        }
    }

    private func moveFence() {
        guard let game else { return }
        let frame = rules.contains(.cursor) ? Self.screen(of: game.processIdentifier) ?? fence?.frame : nil
        #if !APPSTORE
        holdCursor(frame)
        #endif
        guard fence == nil || fence?.frame != frame else { return }
        fence?.stop()
        fence = CursorFence(frame: frame, blocksAll: swipes.blocksAll, except: swipes.except)
    }

    #if !APPSTORE
    private func holdCursor(_ screen: CGRect?) {
        let rects = screen.map { GameRules.fenceRects($0, corners: swipes.corners) } ?? []
        if let cursor = CGEvent(source: nil)?.location, rects.contains(where: { $0.contains(cursor) }) {
            if CursorLock.hold(rects) { cursorHeld = true }
        } else if cursorHeld, CursorLock.hold(nil) {
            cursorHeld = false
        }
    }
    #endif

    private func refreshCommandKeys() {
        ToolRegistry.shared.tools.forEach { ($0 as? CommandKeysTool)?.refresh() }
    }

    private func startTap() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: gameModeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isActive = true
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        swallowed.removeAll()
        isActive = false
    }

    static func key(_ app: NSRunningApplication) -> String {
        GameRules.rule(id: app.bundleIdentifier, name: app.localizedName, path: app.executableURL?.path ?? "")
    }

    static func processFiles(_ text: String) -> [URL] {
        GameRules.processIDs(text) { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return [] }
            return [app.localizedName, app.executableURL?.lastPathComponent].compactMap { $0 }
        }.compactMap { NSRunningApplication(processIdentifier: $0)?.executableURL }
    }

    static func key(_ url: URL) -> String? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == url.path || $0.executableURL?.path == url.path }) {
            return key(app)
        }
        if url.pathExtension == "app", let bundle = Bundle(url: url) {
            return GameRules.rule(id: bundle.bundleIdentifier, name: FileManager.default.displayName(atPath: url.path), path: bundle.executableURL?.path ?? "")
        }
        let file = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        return file && FileManager.default.isExecutableFile(atPath: url.path) ? GameRules.rule(id: nil, name: url.lastPathComponent, path: url.path) : nil
    }

    private func isGame(_ app: NSRunningApplication) -> Bool {
        GameRules.isGame(id: app.bundleIdentifier, name: app.localizedName, path: app.executableURL?.path ?? "", in: games)
    }

    private static func looksLikeGame(_ id: String?, _ url: URL?) -> Bool {
        let info = url.flatMap { NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist")) }
        return GameRules.looksLikeGame(
            id: id,
            category: info?["LSApplicationCategoryType"] as? String,
            supportsGameMode: info?["LSSupportsGameMode"] as? Bool ?? false,
            path: url?.path ?? ""
        )
    }

    #if APPSTORE
    private static var locked = false
    #endif

    static var screenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        #if APPSTORE
        return locked || session?[kCGSessionOnConsoleKey] as? Bool == false
        #else
        return session?["CGSSessionScreenIsLocked"] as? Bool == true || session?[kCGSessionOnConsoleKey] as? Bool == false
        #endif
    }

    private static var savedRules: Set<GameRule> {
        Set(GameRule.allCases.filter { UserDefaults.standard.object(forKey: $0.key) as? Bool ?? true })
    }

    private static var savedCorner: FrameRateCorner {
        FrameRateCorner(rawValue: UserDefaults.standard.string(forKey: frameRateCornerKey) ?? "") ?? .standard
    }

    static func window(of pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> (id: CGWindowID, frame: CGRect)? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return (id, frame)
        }
        return windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }

    // The display that shows the largest part of the window, so a window half off the screen keeps its display.
    static func display(of window: CGRect) -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(window, 16, &displays, &count)
        return displays.prefix(Int(count)).max { a, b in
            let x = CGDisplayBounds(a).intersection(window), y = CGDisplayBounds(b).intersection(window)
            return x.width * x.height < y.width * y.height
        }
    }

    private static func screen(of pid: pid_t) -> CGRect? {
        guard let window = window(of: pid)?.frame, let display = display(of: window) else { return nil }
        return CGDisplayBounds(display)
    }
}


private func gameModeNotification(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    guard let observer, let name else { return }
    Unmanaged<GameModeTool>.fromOpaque(observer).takeUnretainedValue().received(name.rawValue as String)
}

private func gameModeCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tool = Unmanaged<GameModeTool>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = tool.tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .keyDown, .keyUp:
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if type == .keyUp, tool.swallowed.up(Int64(key)) {
            if tool.isPlaying { tool.inputIntent.pressed(Int64(key), down: false) }
            return nil
        }
        guard tool.isPlaying else { break }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let combo = GameRules.combo(key: Int64(key), flags: flags.rawValue)
            if let binding = tool.languageBindings[combo], !event.isPikapik, !binding.automatic || tool.inputIntent.allows(Int64(key), flags: flags, at: event.timestamp) {
                event.markPikapik()
                let pid = tool.game?.processIdentifier
                DispatchQueue.main.async {
                    guard tool.game?.processIdentifier == pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, tool.languageBindings[combo] != nil else { return }
                    InputSwitchTool.selectInGame(binding.direction)
                }
            }
        }
        tool.inputIntent.pressed(Int64(key), down: type == .keyDown)
        guard type == .keyDown else { break }
        let blocked = GameRules.blocksAppShortcut(key: key, flags: flags, rules: tool.rules, allowed: tool.allowedAppShortcuts)
        if blocked || tool.combos.contains(GameRules.combo(key: Int64(key), flags: flags.rawValue)) { tool.hint() }
        #if APPSTORE
        let swallow = blocked || SymbolicHotKeys.swallows(key: key, flags: flags.rawValue)
        #else
        let swallow = blocked
        #endif
        if tool.swallowed.down(Int64(key), swallow: swallow) { return nil }
    case .flagsChanged:
        if tool.isPlaying { tool.inputIntent.changed(event.flags, at: event.timestamp) }
    case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
        event.flags = GameRules.clickFlags(type, event.flags, playing: tool.isPlaying, blocksControl: tool.rules.contains(.controlClick))
    case .scrollWheel:
        GameRules.wheelFlags(event, playing: tool.isPlaying, keepsVertical: tool.rules.contains(.shiftWheel))
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
