import AppKit
import Carbon.HIToolbox
import SwiftUI

#if !APPSTORE
private let alwaysExcluded = HomeEndTool.consoles + ["com.jetbrains.", "com.google.android.studio"]

func replace(_ old: String, with new: String, _ proxy: CGEventTapProxy) {
    func post(_ key: Int, _ text: String?) {
        for down in [true, false] {
            guard let event = CGEvent.pikapikKey(key, down: down, flags: []) else { continue }
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.postPikapik(proxy)
        }
    }
    for _ in old.unicodeScalars { post(kVK_Delete, nil) }
    for character in new { post(0, String(character)) }
}
#endif


@Observable
final class LayoutFixTool: Tool {
    let id = ToolID.layoutFix
    let icon = Symbol.characterCursorIbeam
    var title: String { SettingTitle.layoutFix }

    static let standard = Shortcut(key: 49, modifiers: 0x60000)
    private static let shortcutKey = PreferenceKey.layoutFixShortcut
    #if !APPSTORE
    private static let autoKey = PreferenceKey.layoutFixAuto
    private static let excludedKey = PreferenceKey.layoutFixExcluded
    private static let ignoredKey = PreferenceKey.layoutFixIgnored
    private static let defaultAuto = true
    #endif

    private(set) var isActive = false

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: id)
            refresh()
        }
    }

    #if !APPSTORE
    var fixesAsYouType: Bool {
        didSet {
            UserDefaults.standard.set(fixesAsYouType, forKey: Self.autoKey)
        }
    }
    #endif

    var shortcut: Shortcut {
        didSet {
            if shortcut == Self.standard {
                UserDefaults.standard.removeObject(forKey: Self.shortcutKey)
            } else {
                UserDefaults.standard.set(shortcut.stored, forKey: Self.shortcutKey)
            }
        }
    }

    #if APPSTORE
    var isDefault: Bool { !isEnabled && shortcut == Self.standard }
    #else
    var excluded: [String] {
        didSet { UserDefaults.standard.set(excluded, forKey: Self.excludedKey) }
    }

    var ignored: [String] {
        didSet { UserDefaults.standard.set(ignored, forKey: Self.ignoredKey) }
    }

    var isDefault: Bool { !isEnabled && fixesAsYouType == Self.defaultAuto && shortcut == Self.standard && excluded.isEmpty && ignored.isEmpty }
    #endif

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored fileprivate var holding = false
    #if !APPSTORE
    @ObservationIgnored private var typed: [Stroke] = []
    @ObservationIgnored private var layout: KeyboardLayout?
    @ObservationIgnored private var pid: pid_t = 0
    @ObservationIgnored private var last: (fix: LayoutFix, source: KeyboardLayout)?
    #endif

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: id)
        shortcut = Shortcut(stored: UserDefaults.standard.object(forKey: Self.shortcutKey)) ?? Self.standard
        #if !APPSTORE
        fixesAsYouType = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? Self.defaultAuto
        excluded = UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? []
        ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []
        #endif
    }

    func load() {
        shortcut = Shortcut(stored: UserDefaults.standard.object(forKey: Self.shortcutKey)) ?? Self.standard
        #if !APPSTORE
        fixesAsYouType = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? Self.defaultAuto
        excluded = UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? []
        ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []
        #endif
        isEnabled = UserDefaults.standard.bool(forKey: id)
    }

    func reset() {
        isEnabled = false
        shortcut = Self.standard
        #if !APPSTORE
        fixesAsYouType = Self.defaultAuto
        excluded = []
        ignored = []
        #endif
    }

#if APPSTORE
    // The Services menu works without a permission; the shortcut row asks for Accessibility itself.
    var needs: [Permission] { [] }
    @ObservationIgnored var held: Int64?
    var settingsView: AnyView { AnyView(LayoutFixServiceSettings(tool: self)) }

    func refresh() {
        stop()
        if isEnabled, MainCopy.canAct, AXIsProcessTrusted() { start() }
    }

    private func start() {
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: layoutFixCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isActive = true
    }

    func stop() {
        if held != nil {
            held = nil
            CGEvent.postPikapikKey(kVK_F19, down: false, nil)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        isActive = false
    }
#else
    private func ignore(_ word: String) {
        guard !ignored.contains(word) else { return }
        ignored = Array((ignored + [word]).suffix(200))
    }

    private func select(_ target: KeyboardLayout) {
        TISSelectInputSource(target.source)
        layout = target
    }

    private func allows(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        return !excluded.contains(id) && !alwaysExcluded.contains { id.hasPrefix($0) }
    }

    @ObservationIgnored private var switched: (strokes: [Stroke], layout: KeyboardLayout)?
    @ObservationIgnored private var cycle: (options: [(text: String, layout: KeyboardLayout?)], index: Int, word: String?)?
    var settingsView: AnyView { AnyView(LayoutFixSettings(tool: self)) }

    func refresh() {
        stop()
        if isEnabled, MainCopy.canAct, AXIsProcessTrusted() { start() }
        if !isActive { TextFocus.unwatch(self) }
    }

    private func start() {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: layoutFixCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isActive = true
        DispatchQueue.main.async { KeyboardLayouts.prepare() }
        TextFocus.watch(self)
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        isActive = false
        clear()
    }

    fileprivate func clear() {
        typed = []
        switched = nil
        last = nil
        cycle = nil
    }

    fileprivate func handle(_ event: CGEvent, _ proxy: CGEventTapProxy) -> Bool {
        guard !GameModeTool.shared.isPlaying, !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication, let current = KeyboardLayouts.current else {
            clear()
            return false
        }
        if app.processIdentifier != pid {
            pid = app.processIdentifier
            clear()
        }
        if current.id != layout?.id {
            let stash = typed.contains(where: { $0 != .space }) ? layout.map { (strokes: typed, layout: $0) } : nil
            clear()
            switched = stash
            layout = current
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if Shortcut(key: code, modifiers: flags.rawValue) == shortcut {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return holding }
            guard allows(app), KeyboardLayouts.all.count > 1, let element = field() else {
                clear()
                holding = false
                return false
            }
            holding = convert(element, current, proxy)
            return holding
        }
        if Int(code) == kVK_Space, !flags.isDisjoint(with: [.maskControl, .maskCommand]) { return false }
        switched = nil
        if !flags.isDisjoint(with: [.maskCommand, .maskControl]) {
            clear()
            return false
        }
        if Stroke.keys.contains(code) {
            last = nil
            cycle = nil
            if typed.isEmpty {
                let pid = pid
                DispatchQueue.global(qos: .userInitiated).async {
                    if case .typing(let element) = TextFocus(pid) { _ = TextFocus.value(element, kAXSelectedTextRangeAttribute) }
                }
            }
            typed.append(Stroke(key: code, flags: flags))
            if typed.count > 100 {
                if let space = typed.firstIndex(of: .space) { typed.removeSubrange(...space) } else { clear() }
            }
            return false
        }
        switch Int(code) {
        case kVK_Space where flags.contains(.maskAlternate):
            clear()
            return false
        case kVK_Space:
            return finish(event, proxy, app, current, space: true)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return finish(event, proxy, app, current, space: false)
        case kVK_Delete where !flags.contains(.maskAlternate):
            last = nil
            cycle = nil
            if !typed.isEmpty { typed.removeLast() }
            return false
        default:
            clear()
            return false
        }
    }

    private func finish(_ event: CGEvent, _ proxy: CGEventTapProxy, _ app: NSRunningApplication, _ current: KeyboardLayout, space: Bool) -> Bool {
        if fixesAsYouType, allows(app), KeyboardLayouts.all.count > 1, autoFix(event, proxy, current, space: space) { return true }
        if space {
            last = nil
            cycle = nil
            typed.append(.space)
        } else {
            clear()
        }
        return false
    }

    private func autoFix(_ event: CGEvent, _ proxy: CGEventTapProxy, _ current: KeyboardLayout, space: Bool) -> Bool {
        guard let fix = KeyboardLayouts.fix(typed, from: current, ignored: Set(ignored)), let element = field(),
              Self.matches(element, fix.original, boundary: true) == true else { return false }
        replace(fix.original, with: fix.text, proxy)
        event.copy()?.postPikapik(proxy)
        select(fix.target)
        clear()
        if space { last = (fix, current) }
        return true
    }

    private func convert(_ element: AXUIElement, _ current: KeyboardLayout, _ proxy: CGEventTapProxy) -> Bool {
        if let last, Self.fits(element, last.fix.text + " ") {
            let undo = last.fix.text + " "
            replace(undo, with: last.fix.original + " ", proxy)
            select(last.source)
            let word = KeyboardLayouts.core(String(last.fix.original.split(separator: " ").last ?? ""))?.lowercased()
            if let word { ignore(word) }
            clear()
            cycle = ([(last.fix.original + " ", last.source), (undo, last.fix.target)], 0, word)
            return true
        }
        if let cycle, Self.fits(element, cycle.options[cycle.index].text) {
            let old = cycle.options[cycle.index].text
            let index = (cycle.index + 1) % cycle.options.count
            replace(old, with: cycle.options[index].text, proxy)
            if let target = cycle.options[index].layout { select(target) }
            if let word = cycle.word {
                if index == 0 { ignore(word) } else { ignored.removeAll { $0 == word } }
            }
            self.cycle = (cycle.options, index, cycle.word)
            return true
        }
        if let selected = TextFocus.value(element, kAXSelectedTextAttribute).0 as? String, !selected.isEmpty {
            guard selected.unicodeScalars.count <= 300,
                  !selected.unicodeScalars.contains(where: { "\n\r\t\u{200D}\u{FE0F}".unicodeScalars.contains($0) || $0.properties.isEmojiPresentation }) else { return refuse() }
            let options: [(text: String, layout: KeyboardLayout?)] = KeyboardLayouts.variants(selected).map { ($0.text, nil) } + [(selected, nil)]
            guard options.count > 1 else { return refuse() }
            replace("", with: options[0].text, proxy)
            clear()
            cycle = (options, 0, nil)
            return true
        }
        let pending: (strokes: [Stroke], layout: KeyboardLayout)? = typed.isEmpty ? switched : (typed, current)
        guard let pending, let fix = KeyboardLayouts.fix(pending.strokes, from: pending.layout, forced: true),
              Self.matches(element, fix.original, boundary: false) != false else { return refuse() }
        var options: [(text: String, layout: KeyboardLayout?)] = [(fix.text, fix.target)]
        for target in KeyboardLayouts.targets(after: pending.layout) where target.id != fix.target.id {
            let text = KeyboardLayouts.convert(fix.original, from: pending.layout, to: target)
            if text != fix.original, !options.contains(where: { $0.text == text }) { options.append((text, target)) }
        }
        options.append((fix.original, pending.layout))
        replace(fix.original, with: fix.text, proxy)
        select(fix.target)
        clear()
        cycle = (options, 0, nil)
        return true
    }

    private func refuse() -> Bool {
        NSSound.beep()
        clear()
        return true
    }

    private func field() -> AXUIElement? {
        guard case .typing(let element) = TextFocus(pid),
              TextFocus.value(element, kAXSubroleAttribute).0 as? String != kAXSecureTextFieldSubrole else { return nil }
        return element
    }

    private static func isPlain(_ text: String) -> Bool {
        text.unicodeScalars.count == text.count
    }

    private static func fits(_ element: AXUIElement, _ text: String) -> Bool {
        isPlain(text) && matches(element, text, boundary: false) != false
    }

    private static func matches(_ element: AXUIElement, _ expected: String, boundary: Bool) -> Bool? {
        for attempt in 0..<2 {
            guard let text = before(element, (expected as NSString).length + 1) else { return nil }
            if text.hasSuffix(expected), !boundary || !(text.dropLast(expected.count).last.map { $0.isLetter || $0.isNumber } ?? false) { return true }
            if attempt == 0 { usleep(30_000) }
        }
        return false
    }

    private static func before(_ element: AXUIElement, _ length: Int) -> String? {
        guard let value = TextFocus.value(element, kAXSelectedTextRangeAttribute).0, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        guard range.length == 0 else { return "" }
        var wanted = CFRange(location: max(0, range.location - length), length: min(length, range.location))
        guard let parameter = AXValueCreate(.cfRange, &wanted) else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &text) == .success else { return nil }
        return text as? String
    }
#endif
}

#if APPSTORE
func layoutFixCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tool = Unmanaged<LayoutFixTool>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async { tool.refresh() }
    case .keyDown, .keyUp:
        guard !event.isPikapik else { break }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if tool.held == code {
                tool.held = nil
                CGEvent.postPikapikKey(kVK_F19, down: false, flags: event.flags, proxy)
                return nil
            }
            break
        }
        if !GameModeTool.shared.isPlaying,
           Shortcut(key: UInt16(truncatingIfNeeded: code), modifiers: event.flags.rawValue) == tool.shortcut {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                if tool.holding { return nil }
                break
            }
            tool.holding = true
            if tool.isEnabled {
                tool.held = code
                CGEvent.postPikapikKey(kVK_F19, down: true, flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand], proxy)
                return nil
            }
            tool.holding = false
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

#else
private func layoutFixCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tool = Unmanaged<LayoutFixTool>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async { tool.refresh() }
    case .keyDown where !event.isPikapik:
        if tool.handle(event, proxy) { return nil }
    default:
        tool.clear()
    }
    return Unmanaged.passUnretained(event)
}

#endif
