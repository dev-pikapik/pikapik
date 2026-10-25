import AppKit
import Carbon

enum GameShortcutMode: String, CaseIterable {
    case automatic, pause, background, system

    var title: String {
        switch self {
        case .automatic: String(localized: "Follow Game Mode rules")
        case .pause: String(localized: "Disable in games")
        case .background: String(localized: "Switch language on every press")
        case .system: String(localized: "Allow in games")
        }
    }
}

enum SystemShortcutKind: String, CaseIterable {
    case existing, screenshot, selection, capturePanel, zoom, contrast, invert, voice, captions, presenter, focusMode, brightness, volume, window, language, note, notifications, forceQuit, pointer, other

    var symbol: Symbol {
        switch self {
        case .existing, .other: .gearshapeFill
        case .screenshot, .selection: .cameraFill
        case .capturePanel: .recordCircle
        case .zoom: .plusMagnifyingglass
        case .contrast: .circleLefthalfFilled
        case .invert: .circleDottedCircleFill
        case .voice: .speakerWave2Fill
        case .captions: .captionsBubbleFill
        case .presenter: .personCropCircleFill
        case .focusMode: .moonFill
        case .brightness: .sunMaxFill
        case .volume: .speakerWave2Fill
        case .window: .rectangleSplit2x1
        case .language: .globe
        case .note: .noteText
        case .notifications: .bellFill
        case .forceQuit: .xmarkAppFill
        case .pointer: .computermouse
        }
    }
}

struct SystemGameShortcut: Identifiable {
    let id: Int32
    let name: String
    let section: String
    let sectionName: String
    let rawName: String
    let key: UInt16
    let character: UInt16
    let modifiers: UInt64
    let enabled: Bool
    var pointer: PointerTrigger? = nil

    var emergency: Bool { id == 0 || key == UInt16(kVK_Escape) && modifiers & 0x1C0000 == 0x180000 }
    var assigned: Bool { key != UInt16.max }
    var listed: Bool { SystemShortcutCatalog.nonempty(name) != nil }
    var controller: GameRule? { pointer?.controller ?? Self.controller(id) }
    var supportsBackground: Bool { [60, 61].contains(id) }
    var previewRule: GameRule? { rawName.lowercased().contains("siri") ? .siri : controller }

    var text: String? {
        guard assigned else { return nil }
        return Shortcut.text(character: character, key: key, modifiers: modifiers)
            ?? Shortcut.text(character: Keyboard.character(key), key: key, modifiers: modifiers)
            ?? String(localized: "System key")
    }

    var kind: SystemShortcutKind {
        let raw = rawName.lowercased()
        if pointer != nil { return .pointer }
        if emergency { return .forceQuit }
        if raw.contains("siri") { return .existing }
        if section == "screenshots" {
            return raw.contains("options") || raw.contains("recording") ? .capturePanel : raw.contains("selected area") ? .selection : .screenshot
        }
        if raw.contains("presenter") { return .presenter }
        if raw.contains("caption") || raw.contains("transcri") { return .captions }
        if raw.contains("disturb") { return .focusMode }
        if section == "input_sources" || [60, 61].contains(id) { return .language }
        if raw.contains("brightness") || section == "display" { return .brightness }
        if raw.contains("volume") { return .volume }
        if raw.contains("voiceover") || raw.contains("speak") || raw.contains("speech") || raw.contains("typing feedback") { return .voice }
        if raw.contains("invert") || raw.contains("black and white") { return .invert }
        if raw.contains("contrast") { return .contrast }
        if raw.contains("zoom") && section == "universalaccess" { return .zoom }
        if raw.contains("note") { return .note }
        if raw.contains("notification") { return .notifications }
        if section == "windows" && controller != .hide { return .window }
        if previewRule != nil { return .existing }
        return .other
    }

    static func controller(_ id: Int32) -> GameRule? {
        if [1, 2].contains(id) { return .appSwitcher }
        return GameRule.allCases.first { $0.hotKeys.contains(id) }
    }

    static func overrides(_ values: [String]) -> [Int32: GameShortcutMode] {
        var result: [Int32: GameShortcutMode] = [:]
        for value in values {
            let parts = value.split(separator: ":")
            guard parts.count == 2, let id = Int32(parts[0]), id >= 0 else { continue }
            let mode = parts[1] == "1" ? GameShortcutMode.pause : parts[1] == "0" ? .system : GameShortcutMode(rawValue: String(parts[1]))
            if let mode { result[id] = mode }
        }
        return result
    }

    func mode(rules: Set<GameRule>, overrides: [Int32: GameShortcutMode]) -> GameShortcutMode {
        if emergency { return .system }
        if let choice = overrides[id], choice != .automatic {
            return choice == .background && !supportsBackground ? .pause : choice
        }
        if let controller, !rules.contains(controller) { return .system }
        return supportsBackground ? .background : .pause
    }
}

enum SystemShortcutCatalog {
    static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    struct Metadata {
        let name: String
        let rawName: String
        let section: String
        let sectionName: String
    }

    static func discover(count: Int, known: Set<Int32>, read: (Int32) -> Bool) -> [Int32] {
        var found = Set(known.filter(read))
        var end = min(65_536, max(512, count * 2))
        var start = 0
        repeat {
            for id in start..<end where read(Int32(id)) { found.insert(Int32(id)) }
            if found.count >= count || end == 65_536 { break }
            start = end
            end = min(65_536, end * 2)
        } while true
        return found.sorted()
    }

    static func load() -> [SystemGameShortcut] {
        CFPreferencesAppSynchronize(AppConstants.symbolicHotKeysDomain as CFString)
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        let native = array?.takeRetainedValue() as? [[String: Any]] ?? []
        let metadata = metadata()
        let configured = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, AppConstants.symbolicHotKeysDomain as CFString) as? [String: Any] ?? [:]
        let known = Set(metadata.keys).union(configured.keys.compactMap(Int32.init))
        var values: [Int32: (character: UInt16, key: UInt16, modifiers: UInt64)] = [:]
        let ids = discover(count: status == noErr ? native.count : 300, known: known) { id in
            guard let value = SymbolicHotKeys.value(id) else { return false }
            values[id] = value
            return true
        }
        let paused = Set(HotKeyTrace.ids(.standard) ?? [])
        let buttons = PointerShortcuts.buttons(configured)
        let keyboard = ids.compactMap { id -> SystemGameShortcut? in
            guard let value = values[id], !buttons.contains(id) else { return nil }
            let label = metadata[id]
            let emergency = id == 0 || value.key == UInt16(kVK_Escape) && value.modifiers & 0x1C0000 == 0x180000
            let name = nonempty(label?.name) ?? (emergency ? String(localized: "Force Quit") : legacyName(id)) ?? ""
            let section = label?.section ?? (SystemGameShortcut.controller(id).map { "game-\($0.rawValue)" } ?? "other")
            return SystemGameShortcut(
                id: id, name: name, section: section,
                sectionName: nonempty(label?.sectionName) ?? legacyName(id) ?? String(localized: "Other system shortcuts"),
                rawName: label?.rawName ?? "", key: value.key, character: value.character, modifiers: value.modifiers,
                enabled: paused.contains(id) || SymbolicHotKeys.isEnabled(id)
            )
        }
        let mouse = PointerShortcuts.buttonRows(buttons, metadata: metadata, active: { paused.contains($0) || SymbolicHotKeys.isEnabled($0) }, names: PointerShortcuts.appleNames)
        return keyboard + mouse + PointerShortcuts.load()
    }

    static func selected(_ entries: [SystemGameShortcut], rules: Set<GameRule>, values: [String], appSwitcher: Bool) -> [Int32] {
        var ids = Set(GameRules.hotKeys(rules, appSwitcher: appSwitcher))
        let overrides = SystemGameShortcut.overrides(values)
        for entry in entries where !PointerShortcuts.isSynthetic(entry.id) {
            if entry.mode(rules: rules, overrides: overrides) != .system { ids.insert(entry.id) } else { ids.remove(entry.id) }
        }
        return ids.sorted()
    }

    static func languageBindings(_ entries: [SystemGameShortcut], rules: Set<GameRule>, values: [String], disabled: Set<Int32>) -> [UInt64: (direction: InputSwitchGesture.Direction, automatic: Bool)] {
        let overrides = SystemGameShortcut.overrides(values)
        var result: [UInt64: (direction: InputSwitchGesture.Direction, automatic: Bool)] = [:]
        for entry in entries.sorted(by: { $0.id < $1.id }) where entry.supportsBackground && entry.assigned && disabled.contains(entry.id) {
            guard entry.mode(rules: rules, overrides: overrides) == .background else { continue }
            let key = GameRules.combo(key: Int64(entry.key), flags: entry.modifiers)
            if result[key] == nil {
                result[key] = (entry.id == 60 ? .previous : .next, overrides[entry.id] == nil || overrides[entry.id] == .automatic)
            }
        }
        return result
    }

    private static func legacyName(_ id: Int32) -> String? {
        guard let rule = SystemGameShortcut.controller(id) else { return nil }
        switch rule {
        case .commandQ, .commandW, .controlClick, .shiftWheel, .cursor, .display, .swipes: return nil
        case .appSwitcher: return SettingTitle.gameAppSwitcher
        case .hide: return SettingTitle.gameHide
        case .spotlight: return String(localized: "Spotlight")
        case .siri: return SettingTitle.gameSiri
        case .launchpad: return String(localized: "Launchpad")
        case .missionControl: return String(localized: "Mission Control")
        case .appWindows: return String(localized: "App Exposé")
        case .showDesktop: return String(localized: "Show Desktop")
        case .desktops: return SettingTitle.gameDesktops
        case .desktopNumbers: return SettingTitle.gameDesktopNumbers
        case .emoji: return SettingTitle.gameEmoji
        case .lookUp: return String(localized: "Look Up")
        case .focusKeys: return SettingTitle.gameFocusKeys
        case .globe: return SettingTitle.gameGlobe
        }
    }

    private static func metadata() -> [Int32: Metadata] {
        guard let bundle = Bundle(path: SystemPath.keyboardSettingsExtension) else { return [:] }
        let localized = strings(bundle, "DefaultShortcutsTable")
        let items = bundle.url(forResource: "DefaultShortcutsTable", withExtension: "xml")
            .flatMap { NSArray(contentsOf: $0) as? [[String: Any]] } ?? []
        var result: [Int32: Metadata] = [:]
        func raw(_ item: [String: Any]) -> String { (item["name"] as? String ?? "").replacingOccurrences(of: "DO_NOT_LOCALIZE: ", with: "") }
        func title(_ item: [String: Any]) -> String { nonempty(localized[raw(item)]) ?? raw(item) }
        func walk(_ item: [String: Any], _ section: String, _ sectionName: String, _ context: [(title: String, raw: String)]) {
            for key in ["sybmolichotkey", "slow_sybmolichotkey", "prefs_sybmolichotkey"] {
                if let id = item[key] as? Int32 {
                    result[id] = Metadata(
                        name: (context.suffix(1).map(\.title) + [title(item)]).compactMap(nonempty).joined(separator: " · "),
                        rawName: (context.map(\.raw) + [raw(item)]).compactMap(nonempty).joined(separator: " · "),
                        section: section, sectionName: sectionName
                    )
                }
            }
            for child in item["elements"] as? [[String: Any]] ?? [] { walk(child, section, sectionName, context + [(title(item), raw(item))]) }
        }
        for group in items {
            for child in group["elements"] as? [[String: Any]] ?? [] { walk(child, group["identifier"] as? String ?? "other", title(group), []) }
        }
        for (twin, id) in [16: 15, 18: 17, 20: 19, 22: 21, 154: 53, 166: 53, 170: 53, 155: 54, 165: 54, 169: 54] as [Int32: Int32] where result[twin] == nil {
            result[twin] = result[id]
        }
        if let reader = Bundle(path: SystemPath.accessibilitySettingsExtension),
           let id = reader.url(forResource: "DefaultAccessibilityReaderShortcutsTable", withExtension: "xml").flatMap({ NSArray(contentsOf: $0) as? [[String: Any]] })?.first?["sybmolichotkey"] as? Int32,
           let name = nonempty(strings(reader, "Localizable")["accessibilityReader.title"]),
           let accessibility = result.values.first(where: { $0.section == "universalaccess" }) {
            result[id] = Metadata(name: name, rawName: "Accessibility Reader", section: accessibility.section, sectionName: accessibility.sectionName)
        }
        let dictation = nonempty(strings(bundle, "Localizable")["Dictation.SectionTitle"]) ?? "Dictation"
        result[164] = Metadata(name: dictation, rawName: "Dictation", section: "dictation", sectionName: dictation)
        result[176] = Metadata(name: "Siri", rawName: "Siri", section: "siri", sectionName: "Siri")
        return result
    }

    static func strings(_ bundle: Bundle, _ name: String) -> [String: String] {
        let table = bundle.url(forResource: name, withExtension: "loctable")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]
        let languages = UserDefaults.standard.stringArray(forKey: PreferenceKey.appleLanguages)
        let language = Bundle.preferredLocalizations(from: Array(table.keys), forPreferences: languages).first ?? "en"
        return (table[language] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }
}
