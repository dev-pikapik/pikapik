#if !APPSTORE
import AppKit

struct DesktopIconsHost {
    static let standardKey = "StandardHideDesktopIcons"
    static let stageManagerKey = "HideDesktop"

    let journal: UserDefaults
    let iconsKey: () -> String
    let iconsHidden: (String) -> Bool
    let writeIcons: (String, Bool) -> Void
    let desktopMade: () -> Bool
    let makeDesktop: () -> Void

    static let system = DesktopIconsHost(
        journal: .standard,
        iconsKey: {
            CFPreferencesAppSynchronize(windowManager)
            return CFPreferencesGetAppBooleanValue("GloballyEnabled" as CFString, windowManager, nil) ? stageManagerKey : standardKey
        },
        iconsHidden: { key in
            CFPreferencesAppSynchronize(windowManager)
            var valid: DarwinBoolean = false
            let value = CFPreferencesGetAppBooleanValue(key as CFString, windowManager, &valid)
            return valid.boolValue ? value : key == stageManagerKey
        },
        writeIcons: { key, hidden in
            CFPreferencesSetAppValue(key as CFString, hidden as CFBoolean, windowManager)
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
        host.iconsHidden(host.iconsKey()) || !host.desktopMade()
    }

    static func hide(_ host: DesktopIconsHost) {
        guard !hidden(host) else { return }
        let key = host.iconsKey()
        host.journal.set(key, forKey: written)
        OriginalValue.save(OriginalValue.Entry(before: false, ours: true), original, journal: host.journal)
        host.writeIcons(key, true)
    }

    static func show(_ host: DesktopIconsHost, restartFinder: () -> Void) {
        putBack(host)
        let key = host.iconsKey()
        if host.iconsHidden(key) { host.writeIcons(key, false) }
        guard !host.desktopMade() else { return }
        host.makeDesktop()
        restartFinder()
    }

    static func putBack(_ host: DesktopIconsHost) {
        let key = host.journal.string(forKey: written) ?? host.iconsKey()
        if OriginalValue.putBack(OriginalValue.load(original, journal: host.journal), current: host.iconsHidden(key)) == false { host.writeIcons(key, false) }
        OriginalValue.save(nil, original, journal: host.journal)
        host.journal.removeObject(forKey: written)
    }

    private static let original = "desktop-icons-original"
    private static let written = "desktop-icons-key"
}
#endif
