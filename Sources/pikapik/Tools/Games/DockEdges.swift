import Foundation

#if APPSTORE
enum DockEdges {
    static var journal: [String: Any] { [:] }
    static func calm(corners: Set<Int>, hidesDock: Bool) {}
    static func restoreSoon() {}
    static func restore() {}
}
#else
struct DockHost {
    let journal: UserDefaults
    let read: (String) -> Any?
    let write: (String, Any?) -> Void
    let setCorners: ([String: Int]) -> Bool
    let relaunch: () -> Void

    private static let dock = AppConstants.dockBundleID as CFString

    static let system = DockHost(
        journal: .standard,
        read: { name in
            CFPreferencesAppSynchronize(dock)
            return CFPreferencesCopyAppValue(name as CFString, dock)
        },
        write: { name, value in
            CFPreferencesSetAppValue(name as CFString, value.map { $0 as CFPropertyList }, dock)
            CFPreferencesAppSynchronize(dock)
        },
        setCorners: DockCorners.set,
        relaunch: {
            CFPreferencesAppSynchronize(dock)
            _ = try? Process.run(URL(fileURLWithPath: SystemPath.killall), arguments: ["Dock"])
        }
    )

    static func offline(_ relaunch: @escaping () -> Void) -> DockHost {
        DockHost(journal: .standard, read: system.read, write: system.write, setCorners: { $0.isEmpty }, relaunch: relaunch)
    }
}

enum DockEdges {
    private static let key = PreferenceKey.gameModeDock
    private static let corners = ["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"], delay = "autohide-delay"
    private static var pending: DispatchWorkItem?
    static var journal: [String: Any] { stored(.system) }
    static func calm(corners wanted: Set<Int>, hidesDock: Bool, _ host: DockHost = .system) {
        pending?.cancel()
        pending = nil
        let saved = stored(host)
        func current(_ name: String) -> Int { ((saved[name] ?? host.read(name)) as? NSNumber)?.intValue ?? 0 }
        let active = wanted.sorted().map { corners[$0] }.filter { current($0) > 1 }
        let hides = hidesDock && host.read("autohide") as? Bool ?? false
        let targets = active + (hides ? [delay] : [])
        var restart = false
        if !saved.isEmpty {
            guard Set(saved.keys) != Set(targets) else { return }
            restart = reset(host)
        }
        if !targets.isEmpty {
            var original: [String: Any] = [:]
            for name in targets { original[name] = host.read(name) ?? "" }
            host.journal.set(original, forKey: key)
            for name in active { host.write(name, 1) }
            if hides { host.write(delay, 1000.0) }
            restart = !host.setCorners(Dictionary(uniqueKeysWithValues: active.map { ($0, 1) })) || hides || restart
        }
        if restart { host.relaunch() }
    }
    static func restoreSoon() {
        guard UserDefaults.standard.dictionary(forKey: key) != nil, pending == nil else { return }
        let work = DispatchWorkItem { restore() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
    static func restore(_ host: DockHost = .system) {
        pending?.cancel()
        pending = nil
        guard !stored(host).isEmpty, reset(host) else { return }
        host.relaunch()
    }
    static func read(_ name: String, _ host: DockHost = .system) -> Any? {
        guard let held = underneath(name, host) else { return host.read(name) }
        return held
    }
    @discardableResult static func write(_ name: String, _ value: Any?, _ host: DockHost = .system) -> Bool {
        if underneath(name, host) != nil {
            var saved = stored(host)
            saved[name] = value ?? ""
            host.journal.set(saved, forKey: key)
            return false
        }
        host.write(name, value)
        return true
    }
    static func restorable(_ saved: [String: Any], current: (String) -> Any?) -> [String: Any] {
        saved.filter { name, _ in
            let value = (current(name) as? NSNumber)?.doubleValue
            return name == delay ? value == 1000 : value == 0 || value == 1
        }
    }
    private static func underneath(_ name: String, _ host: DockHost) -> Any?? {
        guard let original = stored(host)[name], !restorable([name: original], current: host.read).isEmpty else { return nil }
        return .some(original as? String == "" ? nil : original)
    }
    private static func stored(_ host: DockHost) -> [String: Any] {
        host.journal.dictionary(forKey: key) ?? [:]
    }
    private static func reset(_ host: DockHost) -> Bool {
        let ours = restorable(stored(host), current: host.read)
        var live: [String: Int] = [:]
        for (name, original) in ours {
            host.write(name, original as? String == "" ? nil : original)
            if name != delay { live[name] = (original as? NSNumber)?.intValue ?? 1 }
        }
        host.journal.removeObject(forKey: key)
        return ours[delay] != nil || !host.setCorners(live)
    }
}
#endif
