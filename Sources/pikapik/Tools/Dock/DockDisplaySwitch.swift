import CoreGraphics
import Foundation

/// The Dock's own `allow-display-switching` key: nil is a missing key, which the Dock reads as true.
enum DockDisplaySwitch {
    static let ownedKey = "dock-display-owned", beforeKey = "dock-display-before"

    static func plan(on: Bool, current: Bool?, owned: Bool, before: Bool?) -> (value: Bool?, before: Bool?, restart: Bool) {
        let old = owned ? before : current
        let value = on ? false : (owned && current != false ? current : old)
        return (value, on ? old : nil, (value ?? true) != (current ?? true))
    }

    static func apply(_ on: Bool, current: Bool?, write: (Bool?) -> Void) -> Bool {
        let defaults = UserDefaults.standard
        let result = plan(on: on, current: current, owned: defaults.bool(forKey: ownedKey), before: defaults.object(forKey: beforeKey) as? Bool)
        if on {
            defaults.set(true, forKey: ownedKey)
            defaults.set(result.before, forKey: beforeKey)
        }
        if result.value != current { write(result.value) }
        if !on {
            defaults.set(false, forKey: ownedKey)
            defaults.removeObject(forKey: beforeKey)
        }
        return result.restart
    }
}

/// Display origins by display UUID: the main display always sits at (0, 0), and the others keep their place relative to it.
enum MainDisplay {
    struct Saved: Equatable {
        var origins: [String: CGPoint]
        var main: String?
    }

    static func origins(_ displays: [(uuid: String, origin: CGPoint)]) -> [String: CGPoint]? {
        let origins = Dictionary(displays.map { ($0.uuid, $0.origin) }, uniquingKeysWith: { first, _ in first })
        return origins.count == displays.count ? origins : nil
    }

    static func moved(_ origins: [String: CGPoint], to main: String) -> [String: CGPoint]? {
        guard let anchor = origins[main], anchor != .zero else { return nil }
        return origins.mapValues { CGPoint(x: $0.x - anchor.x, y: $0.y - anchor.y) }
    }

    static func set(_ origins: [String: CGPoint]) -> String {
        origins.keys.sorted().joined(separator: " ")
    }

    static func remembered(_ journal: [String: Saved], now: [String: CGPoint], main: String) -> [String: Saved] {
        var journal = journal
        journal[set(now)] = Saved(origins: journal[set(now)]?.origins ?? now, main: main)
        return journal
    }

    static func restored(_ journal: [String: Saved], now: [String: CGPoint]) -> (write: [String: CGPoint]?, journal: [String: Saved]) {
        guard let saved = journal[set(now)] else { return (nil, journal) }
        var rest = journal
        rest[set(now)] = nil
        let ours = saved.main.map { now[$0] == .zero } ?? true
        return (saved.origins != now && ours ? saved.origins : nil, rest)
    }

    static func journal(_ stored: [String: Any]?, old: [String: [Double]]?) -> [String: Saved] {
        var journal = (stored ?? [:]).compactMapValues { value -> Saved? in
            guard let entry = value as? [String: Any], let origins = (entry["origins"] as? [String: [Double]]).map(points), !origins.isEmpty else { return nil }
            return Saved(origins: origins, main: entry["main"] as? String)
        }
        if let origins = old.map(points), !origins.isEmpty, journal[set(origins)] == nil {
            journal[set(origins)] = Saved(origins: origins, main: nil)
        }
        return journal
    }

    static func stored(_ journal: [String: Saved]) -> [String: Any] {
        journal.mapValues { saved in
            var entry: [String: Any] = ["origins": saved.origins.mapValues { [Double($0.x), Double($0.y)] }]
            if let main = saved.main { entry["main"] = main }
            return entry
        }
    }

    private static func points(_ values: [String: [Double]]) -> [String: CGPoint] {
        values.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }
}
