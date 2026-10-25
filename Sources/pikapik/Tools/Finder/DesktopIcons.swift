#if !APPSTORE
import AppKit

struct DesktopIconsHost {
    static let standardKey = "StandardHideDesktopIcons"
    static let stageManagerKey = "HideDesktop"

    let journal: UserDefaults
    let iconsKey: () -> String
    let iconsValue: (String) -> Bool?
    let writeIcons: (String, Bool?) -> Void
    let desktopMade: () -> Bool
    let makeDesktop: () -> Void

    static let system = DesktopIconsHost(
        journal: .standard,
        iconsKey: {
            CFPreferencesAppSynchronize(windowManager)
            return CFPreferencesGetAppBooleanValue("GloballyEnabled" as CFString, windowManager, nil) ? stageManagerKey : standardKey
        },
        iconsValue: { key in
            CFPreferencesAppSynchronize(windowManager)
            var valid: DarwinBoolean = false
            let value = CFPreferencesGetAppBooleanValue(key as CFString, windowManager, &valid)
            return valid.boolValue ? value : nil
        },
        writeIcons: { key, hidden in
            CFPreferencesSetAppValue(key as CFString, hidden.map { $0 as CFBoolean }, windowManager)
            CFPreferencesAppSynchronize(windowManager)
            _ = try? Process.run(URL(fileURLWithPath: SystemPath.killall), arguments: ["WindowManager"])
        },
        desktopMade: {
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return false }
            let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            return list.contains {
                $0[kCGWindowOwnerPID as String] as? pid_t == finder.processIdentifier
                    && $0[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.desktopIconWindow))
            }
        },
        makeDesktop: {
            CFPreferencesSetAppValue("CreateDesktop" as CFString, nil, finder)
            CFPreferencesAppSynchronize(finder)
        }
    )

    private static let windowManager = "com.apple.WindowManager" as CFString
    private static let finder = "com.apple.finder" as CFString
}

enum DesktopIcons {
    static func hidden(_ host: DesktopIconsHost) -> Bool {
        iconsHidden(host, host.iconsKey()) || !host.desktopMade()
    }

    static func hide(_ host: DesktopIconsHost) {
        guard !hidden(host) else { return }
        let key = host.iconsKey()
        host.journal.set(key, forKey: written)
        host.journal.set(host.iconsValue(key) == nil, forKey: missing)
        OriginalValue.save(OriginalValue.Entry(before: false, ours: true), original, journal: host.journal)
        host.writeIcons(key, true)
    }

    static func show(_ host: DesktopIconsHost, restartFinder: () -> Void) {
        putBack(host)
        let key = host.iconsKey()
        if iconsHidden(host, key) { host.writeIcons(key, false) }
        guard !host.desktopMade() else { return }
        host.makeDesktop()
        restartFinder()
    }

    static func putBack(_ host: DesktopIconsHost) {
        let key = host.journal.string(forKey: written) ?? host.iconsKey()
        if OriginalValue.putBack(OriginalValue.load(original, journal: host.journal), current: iconsHidden(host, key)) == false {
            host.writeIcons(key, host.journal.bool(forKey: missing) ? nil : false)
        }
        OriginalValue.save(nil, original, journal: host.journal)
        host.journal.removeObject(forKey: written)
        host.journal.removeObject(forKey: missing)
    }

    private static func iconsHidden(_ host: DesktopIconsHost, _ key: String) -> Bool {
        host.iconsValue(key) ?? (key == DesktopIconsHost.stageManagerKey)
    }

    private static let original = "desktop-icons-original"
    private static let written = "desktop-icons-key"
    private static let missing = "desktop-icons-missing"
}
#endif
