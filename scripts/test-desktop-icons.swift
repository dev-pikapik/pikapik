import AppKit

@main
struct TestDesktopIcons {
    final class Mac {
        var keys: [String: Bool] = [:]
        var stageManager = false
        var createDesktop = true
        var desktop = true
        var iconWrites = 0
        var finderRestarts = 0

        var key: String { stageManager ? DesktopIconsHost.stageManagerKey : DesktopIconsHost.standardKey }
        var icons: Bool {
            get { hidden(key) }
            set { keys[key] = newValue }
        }

        func hidden(_ key: String) -> Bool { keys[key] ?? (key == DesktopIconsHost.stageManagerKey) }

        func restartFinder() {
            finderRestarts += 1
            desktop = createDesktop
        }

        func copy(_ journal: UserDefaults) -> DesktopIconsHost {
            DesktopIconsHost(
                journal: journal,
                iconsKey: { self.key },
                iconsValue: { self.keys[$0] },
                writeIcons: { self.keys[$0] = $1; self.iconWrites += 1 },
                desktopMade: { self.desktop },
                makeDesktop: { self.createDesktop = true }
            )
        }
    }

    static let key = "desktop-icons-original"
    static let hiddenByUs = OriginalValue.Entry(before: false, ours: true)
    static let hiddenBefore = OriginalValue.Entry(before: true, ours: false)

    static func main() {
        var suites: [String] = []
        func journal(_ name: String) -> UserDefaults {
            let suite = "test-desktop-icons-\(name)"
            suites.append(suite)
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite)!
        }

        do {
            let mac = Mac()
            mac.createDesktop = false
            mac.desktop = false
            let copy = mac.copy(journal("owner"))
            precondition(DesktopIcons.hidden(copy), "with CreateDesktop off the switch must show the icons as hidden")
            DesktopIcons.show(copy) { mac.restartFinder() }
            precondition(mac.createDesktop && mac.desktop && !DesktopIcons.hidden(copy), "turning the switch off must bring the desktop back")
            precondition(mac.finderRestarts == 1 && mac.iconWrites == 0)
            mac.desktop = false
            precondition(DesktopIcons.hidden(copy))
            DesktopIcons.show(copy) { mac.restartFinder() }
            precondition(mac.desktop && mac.finderRestarts == 2)
        }
        print("a Finder without its desktop shows as hidden, and turning the switch off restarts Finder with the desktop: ok")

        do {
            let mac = Mac()
            let saved = journal("quit")
            let copy = mac.copy(saved)
            precondition(!DesktopIcons.hidden(copy))
            DesktopIcons.hide(copy)
            precondition(mac.icons && DesktopIcons.hidden(copy) && OriginalValue.load(key, journal: saved) == hiddenByUs)
            DesktopIcons.putBack(copy)
            precondition(!mac.icons && OriginalValue.load(key, journal: saved) == nil && mac.finderRestarts == 0)
        }
        print("turning the switch on hides the icons, and quitting brings them back: ok")

        do {
            let mac = Mac()
            mac.icons = true
            let copy = mac.copy(journal("settings"))
            precondition(DesktopIcons.hidden(copy))
            DesktopIcons.putBack(copy)
            precondition(mac.icons && mac.iconWrites == 0, "quitting must not touch icons hidden in System Settings")
            DesktopIcons.show(copy) { mac.restartFinder() }
            precondition(!mac.icons)
            DesktopIcons.putBack(copy)
            precondition(!mac.icons && mac.iconWrites == 1, "quitting must not hide the icons again")
        }
        print("icons hidden in System Settings stay hidden on quit, and once turned off they stay visible: ok")

        do {
            let mac = Mac()
            let saved = journal("old")
            let copy = mac.copy(saved)
            OriginalValue.save(hiddenBefore, key, journal: saved)
            DesktopIcons.putBack(copy)
            precondition(!mac.icons && OriginalValue.load(key, journal: saved) == nil, "an old journal must never hide the icons")
            OriginalValue.save(hiddenBefore, key, journal: saved)
            DesktopIcons.hide(copy)
            precondition(mac.icons && OriginalValue.load(key, journal: saved) == hiddenByUs)
            DesktopIcons.putBack(copy)
            precondition(!mac.icons, "icons hidden over an old journal must come back on quit")
        }
        print("a journal from an older version that remembers hidden icons never hides them again: ok")

        do {
            let mac = Mac()
            mac.icons = true
            let saved = journal("update")
            OriginalValue.save(hiddenByUs, key, journal: saved)
            DesktopIcons.putBack(mac.copy(saved))
            precondition(!mac.icons && OriginalValue.load(key, journal: saved) == nil)
        }
        print("icons that a copy hid and never put back come back at the next launch: ok")

        do {
            let mac = Mac()
            let website = journal("website"), dev = journal("dev")
            DesktopIcons.hide(mac.copy(website))
            DesktopIcons.show(mac.copy(dev)) { mac.restartFinder() }
            DesktopIcons.putBack(mac.copy(dev))
            DesktopIcons.putBack(mac.copy(website))
            precondition(!mac.icons, "two copies must quit with the icons visible")
            DesktopIcons.hide(mac.copy(dev))
            DesktopIcons.hide(mac.copy(website))
            precondition(OriginalValue.load(key, journal: website) == nil)
            DesktopIcons.putBack(mac.copy(website))
            precondition(mac.icons)
            DesktopIcons.putBack(mac.copy(dev))
            precondition(!mac.icons)
        }
        print("two copies: the copy that hid the icons brings them back, and the other one never hides them: ok")

        do {
            let mac = Mac()
            mac.createDesktop = false
            mac.desktop = false
            let saved = journal("still")
            DesktopIcons.hide(mac.copy(saved))
            precondition(!mac.icons && mac.iconWrites == 0 && OriginalValue.load(key, journal: saved) == nil)
            mac.createDesktop = true
            mac.desktop = true
            DesktopIcons.show(mac.copy(saved)) { mac.restartFinder() }
            precondition(mac.iconWrites == 0 && mac.finderRestarts == 0)
        }
        print("a switch that already matches the desktop writes nothing and restarts nothing: ok")

        do {
            let stage = DesktopIconsHost.stageManagerKey
            let mac = Mac()
            let saved = journal("stage-manager-on")
            DesktopIcons.hide(mac.copy(saved))
            mac.stageManager = true
            precondition(DesktopIcons.hidden(mac.copy(saved)), "Stage Manager hides desktop items until you show them")
            DesktopIcons.putBack(mac.copy(saved))
            precondition(mac.keys.isEmpty, "quitting after Stage Manager was turned on must show the icons again and leave Stage Manager's own setting alone: \(mac.keys)")

            mac.keys = [stage: false]
            let other = journal("stage-manager-off")
            DesktopIcons.hide(mac.copy(other))
            precondition(mac.keys == [stage: true])
            mac.stageManager = false
            DesktopIcons.putBack(mac.copy(other))
            precondition(mac.keys == [stage: false], "quitting after Stage Manager was turned off must give Stage Manager back its desktop items: \(mac.keys)")

            mac.keys = [:]
            let switched = journal("stage-manager-switch")
            DesktopIcons.hide(mac.copy(switched))
            mac.stageManager = true
            DesktopIcons.show(mac.copy(switched)) { mac.restartFinder() }
            precondition(mac.keys == [stage: false] && !DesktopIcons.hidden(mac.copy(switched)), "turning the switch off shows the icons in both modes: \(mac.keys)")
            DesktopIcons.putBack(mac.copy(switched))
            precondition(mac.keys == [stage: false] && mac.finderRestarts == 0)
        }
        print("turning Stage Manager on or off while the icons are hidden puts back only the setting pikapik changed: ok")

        do {
            let standard = DesktopIconsHost.standardKey
            let mac = Mac()
            let saved = journal("missing")
            DesktopIcons.hide(mac.copy(saved))
            precondition(mac.keys == [standard: true])
            DesktopIcons.putBack(mac.copy(saved))
            precondition(mac.keys.isEmpty, "quitting must take away a key that had no value, not set it to false: \(mac.keys)")

            mac.keys = [standard: false]
            DesktopIcons.hide(mac.copy(saved))
            DesktopIcons.putBack(mac.copy(saved))
            precondition(mac.keys == [standard: false], "a key that was set to false must stay set to false: \(mac.keys)")

            mac.keys = [:]
            DesktopIcons.hide(mac.copy(saved))
            DesktopIcons.show(mac.copy(saved)) { mac.restartFinder() }
            precondition(mac.keys.isEmpty && mac.finderRestarts == 0, "turning the switch off must also take away a key that had no value: \(mac.keys)")
        }
        print("a desktop icons key that had no value is taken away again instead of being set to false: ok")

        suites.forEach(UserDefaults.standard.removePersistentDomain)
    }
}
