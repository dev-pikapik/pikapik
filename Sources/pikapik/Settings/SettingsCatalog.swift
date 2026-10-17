import SwiftUI

struct SettingsItem: Identifiable {
    let tab: SettingsTab
    let title: String
    var synonyms = ""
    var target: String?
    var detail: String?
    var keys = ""
    var directOnly = false

    var id: String { target ?? title }

    static func shortcut(_ entry: SystemGameShortcut) -> SettingsItem {
        SettingsItem(tab: .games, title: entry.name,
                     synonyms: [entry.rawName, entry.sectionName, entry.group.title, entry.group.detail, entry.description.text, entry.supportsBackground ? String(localized: "Switch language") + ", Switch language" : "", "game games gaming", String(entry.id)].joined(separator: ", "),
                     target: entry.anchor, detail: [entry.group.title, entry.text ?? (entry.pointer == nil ? String(localized: "No key assigned") : entry.pointer?.detail)].compactMap { $0 }.joined(separator: " · "), keys: entry.text ?? "")
    }

    static var all: [SettingsItem] {
        #if APPSTORE
        let hasArchives = ToolRegistry.shared.tools.contains { $0 is ArchiveTool }
        return allItems.filter {
            $0.tab.isAvailable && !$0.directOnly
                && (SettingsSync.isAvailable || $0.id != String(localized: "Sync settings with iCloud"))
                && (hasArchives || $0.id != String(localized: "Archives in Finder"))
        } + [
            SettingsItem(tab: .animations, title: String(localized: "Hide the Dock automatically"), synonyms: "autohide, hide Dock, delay, wait"),
            SettingsItem(tab: .keyboard, title: String(localized: "Fix the selected text"), synonyms: "shortcut, undo, convert, selection, layout"),
            SettingsItem(tab: .permissions, title: String(localized: "Folders"), synonyms: "privacy, security, access, files, save, home"),
            SettingsItem(tab: .about, title: String(localized: "Say thanks"), synonyms: "support, donate, donation, tip, sponsor, thanks"),
        ] + Permissions.privacyLists.map {
            SettingsItem(tab: .permissions, title: $0.title, target: $0.pane, detail: String(localized: "Other apps’ permissions"))
        }
        #else
        return allItems.filter { $0.tab.isAvailable }
        #endif
    }

    private static var allItems: [SettingsItem] {
        [
            SettingsItem(tab: .general, title: String(localized: "Open at Login"), synonyms: "launch, startup, autostart, login items"),
            SettingsItem(tab: .general, title: String(localized: "Stay in the background after Quit"), synonyms: "background, quit, close, exit, hide, menu bar icon, option", directOnly: true),
            SettingsItem(tab: .general, title: String(localized: "Appearance"), synonyms: "theme, dark mode, light mode, colors"),
            SettingsItem(tab: .general, title: String(localized: "Language"), synonyms: "localization, translation"),
            SettingsItem(tab: .general, title: String(localized: "Settings file"), synonyms: "backup, export, import, restore, JSON"),
            SettingsItem(tab: .general, title: String(localized: "Sync settings with iCloud"), synonyms: "iCloud Drive, another Mac, backup"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Keep your Mac awake"), synonyms: "sleep, caffeine, insomnia"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Duration"), synonyms: "time, timer, days, hours, minutes, seconds"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Display"), synonyms: "screen, monitor, dim, screen saver"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Turn off the display now"), synonyms: "screen, monitor, dim, screen saver"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Buttons in Control Center and widgets"), synonyms: "widget, Control Center, Shortcuts, menu bar, button"),
        ] + (KeepAwake.shared.hasLid ? [
            SettingsItem(tab: .keepAwake, title: String(localized: "Work with the lid closed"), synonyms: "clamshell, laptop, MacBook, external display"),
            SettingsItem(tab: .keepAwake, title: String(localized: "Stop when battery is below \(0.2.formatted(.percent))"), synonyms: "battery, power, charge"),
        ] : []) + [
            SettingsItem(tab: .brightness, title: String(localized: "Brightness"), synonyms: "monitor, display, screen, external display, dim, dimmer, brighter, darker, DDC, backlight"),
            SettingsItem(tab: .brightness, title: String(localized: "Brightness keys"), synonyms: "keyboard, F1, F2, brightness up, brightness down, keys, monitor, display"),
            SettingsItem(tab: .brightness, title: String(localized: "Dim the picture instead"), synonyms: "gamma, dim, darker, software dimming, monitor, display, screen", directOnly: true),
            SettingsItem(tab: .battery, title: String(localized: "Battery Health"), synonyms: "battery, condition, maximum capacity, cycle count, cycles, wear, service, replace"),
            SettingsItem(tab: .battery, title: String(localized: "Power Adapter"), synonyms: "charger, charging, watts, power use, adapter, plug"),
            SettingsItem(tab: .battery, title: String(localized: "Keep It Healthy"), synonyms: "charge limit, 80%, optimized battery charging, charging on hold, heat, temperature, storage, tips"),
            SettingsItem(tab: .fans, title: String(localized: "Fan speed"), synonyms: "fan, rpm, cooling, cooler, hot, heat, noise, quiet, loud, temperature, thermal"),
            SettingsItem(tab: .permissions, title: String(localized: "Administrator access"), synonyms: "allow, helper, password, administrator, install, remove", directOnly: true),
            SettingsItem(tab: .temperatures, title: String(localized: "Temperature"), synonyms: "heat, hot, warm, thermal, sensors, CPU, GPU, processor, graphics, memory, RAM, SSD, storage, battery, Wi-Fi, degrees, Celsius, Fahrenheit, overheating"),
            SettingsItem(tab: .speedTest, title: String(localized: "Check Speed"), synonyms: "internet, Wi-Fi, network, bandwidth, ping, Mbps, speedtest"),
            SettingsItem(tab: .speedTest, title: String(localized: "What it’s good for"), synonyms: "4K, video, calls, games, downloads"),
            SettingsItem(tab: .ports, title: String(localized: "Free a port"), synonyms: "port, server, localhost, listen, kill, lsof, address in use, EADDRINUSE, process, 3000, 8080, 5000, AirPlay"),
            SettingsItem(tab: .sound, title: String(localized: "App Volume"), synonyms: "mixer, mute app, per-app volume, volume, sound, audio, quiet, loud"),
            SettingsItem(tab: .keyboard, title: String(localized: "Switch language"), synonyms: "keyboard layout, input source, option, shift, alt"),
            SettingsItem(tab: .keyboard, title: String(localized: "Repeat a held key"), synonyms: "key repeat, hold, accent menu, games, typing", directOnly: true),
            SettingsItem(tab: .keyboard, title: String(localized: "Home and End go to the start and end of a line"), synonyms: "home, end, line, cursor, beginning, select, text, typing"),
            SettingsItem(tab: .keyboard, title: String(localized: "Home and End work as usual in these apps"), synonyms: "exceptions, exclude, list, terminal, virtual machine, remote desktop"),
            SettingsItem(tab: .keyboard, title: String(localized: "Retype words you typed in the wrong language"), synonyms: "wrong layout, keyboard layout, language, switch, convert, typo, gibberish, Services"),
            SettingsItem(tab: .keyboard, title: String(localized: "Fix words as you type"), synonyms: "automatic, auto, Space, Return, layout"),
            SettingsItem(tab: .keyboard, title: String(localized: "Fix the last word or selected text"), synonyms: "shortcut, undo, convert, selection, layout", directOnly: true),
            SettingsItem(tab: .keyboard, title: String(localized: "Don’t fix text in these apps"), synonyms: "exceptions, exclude, list, layout"),
            SettingsItem(tab: .mouse, title: String(localized: "Turn off pointer acceleration"), synonyms: "linear, mouse acceleration, sensitivity"),
            SettingsItem(tab: .mouse, title: String(localized: "Tracking speed"), synonyms: "pointer speed, sensitivity, fast, slow", directOnly: true),
            SettingsItem(tab: .mouse, title: String(localized: "Scroll by lines"), synonyms: "wheel, scrolling speed, acceleration"),
            SettingsItem(tab: .mouse, title: String(localized: "Distance per click"), synonyms: "scrolling speed, wheel, notch"),
            SettingsItem(tab: .mouse, title: String(localized: "Scroll by"), synonyms: "pixels, lines, wheel, games, scrolling mode, notch"),
            SettingsItem(tab: .mouse, title: String(localized: "Scroll direction for trackpad and mouse"), synonyms: "natural scrolling, classic, reverse, invert, Universal Control, trackpad, mouse, Magic Mouse, wheel, direction"),
            SettingsItem(tab: .mouse, title: String(localized: "Trackpad direction"), synonyms: "natural, classic, reverse, invert, trackpad, two fingers, Magic Mouse, up, down"),
            SettingsItem(tab: .mouse, title: String(localized: "Mouse wheel direction"), synonyms: "natural, classic, reverse, invert, wheel, up, down"),
            SettingsItem(tab: .mouse, title: String(localized: "Side buttons go back and forward"), synonyms: "buttons 4 and 5, browser, navigation, thumb buttons"),
            SettingsItem(tab: .mouse, title: String(localized: "Swap the side buttons"), synonyms: "reverse, back, forward"),
            SettingsItem(tab: .mouse, title: String(localized: "Mouse button hides the current app"), synonyms: "hide, ⌘H, cmd H, middle button, button 4, button 5, mouse button"),
            SettingsItem(tab: .mouse, title: String(localized: "Middle click on the trackpad"), synonyms: "middle button, wheel click, three fingers, four fingers, tap, open link in new tab, close tab", directOnly: true),
            SettingsItem(tab: .mouse, title: String(localized: "Fingers"), synonyms: "middle click, three, four, tap, click, trackpad", directOnly: true),
            SettingsItem(tab: .windows, title: String(localized: "Green button enlarges the window"), synonyms: "zoom, maximize, full screen, green button, option click", directOnly: true),
            SettingsItem(tab: .windows, title: String(localized: "Green button works as usual in these apps"), synonyms: "exceptions, exclude, list", directOnly: true),
            SettingsItem(tab: .windows, title: String(localized: "Protect quitting and closing"), synonyms: "quit, close, command, accidental, shortcut"),
            SettingsItem(tab: .windows, title: String(localized: "Quit app"), synonyms: "change shortcut, record keys, Command Shift Q"),
            SettingsItem(tab: .windows, title: String(localized: "Close window"), synonyms: "change shortcut, record keys, Command Shift W"),
            SettingsItem(tab: .windows, title: String(localized: "Quit when the last window closes"), synonyms: "close button, red button, terminate, exit", directOnly: true),
            SettingsItem(tab: .windows, title: String(localized: "Never quit these apps"), synonyms: "exceptions, exclude, list", directOnly: true),
            SettingsItem(tab: .dock, title: String(localized: "Minimize or hide with a click in the Dock"), synonyms: "Dock, minimize, hide, taskbar", directOnly: true),
            SettingsItem(tab: .dock, title: String(localized: "A click on the icon"), synonyms: "Dock, minimize, hide, taskbar", directOnly: true),
            SettingsItem(tab: .dock, title: String(localized: "Keep the Dock on one display"), synonyms: "Dock, display, monitor, screen, jump, move"),
            SettingsItem(tab: .dock, title: String(localized: "Main display"), synonyms: "primary, main screen, Displays settings"),
            SettingsItem(tab: .finder, title: String(localized: "New File in Finder"), synonyms: "create, text file, txt, right-click, context menu, Desktop"),
            SettingsItem(tab: .finder, title: String(localized: "Smaller Copy in Finder"), synonyms: "compress, shrink, smaller, reduce size, optimize, image, photo, picture, video, audio, music, PNG, JPEG, JPG, HEIC, TIFF, PDF, GIF, MP4, MOV, M4A, WAV, AIFF, TinyPNG"),
            SettingsItem(tab: .finder, title: String(localized: "Convert in Finder"), synonyms: "convert, format, export, save as, image, photo, picture, video, audio, music, PNG, JPEG, JPG, HEIC, TIFF, PDF, GIF, MP4, MOV, M4A, WAV, AIFF"),
            SettingsItem(tab: .finder, title: String(localized: "Archives in Finder"), synonyms: "archive, extract, unzip, unpack, zip, rar, 7z, tar, password, split, right-click, context menu"),
            SettingsItem(tab: .finder, title: String(localized: "Open archives in pikapik"), synonyms: "archive, default app, open with, double-click, unzip, zip, 7z", directOnly: true),
            SettingsItem(tab: .finder, title: String(localized: "Enter opens files in Finder"), synonyms: "return, enter, open, rename, F2, keyboard", directOnly: true),
            SettingsItem(tab: .finder, title: String(localized: "Cut files in Finder"), synonyms: "cut, paste, move, files, folders, command X"),
            SettingsItem(tab: .finder, title: String(localized: "Delete removes files in Finder"), synonyms: "delete, backspace, trash, remove, files, folders, keyboard", directOnly: true),
            SettingsItem(tab: .finder, title: String(localized: "Hide desktop icons"), synonyms: "desktop, icons, files, folders, clean, hide, presentation, screen sharing, recording, screenshot, Stage Manager"),
            SettingsItem(tab: .finder, title: String(localized: "Show hidden files"), synonyms: "hidden, invisible, dot files, system files, Library, show all files, Command Shift Period"),
            SettingsItem(tab: .player, title: String(localized: "Open Video…"), synonyms: "video, movie, film, watch, play, mkv, avi, wmv, webm, flv"),
            SettingsItem(tab: .player, title: String(localized: "Open videos in pikapik"), synonyms: "default app, open with, double-click, video, movie, mkv, avi, webm, mp4, mov, QuickTime"),
            SettingsItem(tab: .player, title: String(localized: "Open music in pikapik"), synonyms: "music, song, audio, flac, mp3, ogg, opus, wma, default app, open with, double-click"),
            SettingsItem(tab: .player, title: String(localized: "Open pictures in pikapik"), synonyms: "photo, image, picture, jpeg, jpg, png, heic, webp, avif, gif, raw, psd, tiff, svg, default app, open with, double-click, Preview"),
            SettingsItem(tab: .player, title: String(localized: "Player Licenses"), synonyms: "open source, legal, FFmpeg, dav1d, libass, FreeType, HarfBuzz, FriBidi"),
            SettingsItem(tab: .uninstaller, title: String(localized: "Remove an app"), synonyms: "uninstall, remove app, delete app, delete, remove, app, application, cleaner, clean up, leftovers, trash, reset, put back, restore, undo"),
            SettingsItem(tab: .uninstaller, title: String(localized: "Offer to clean up when an app goes to the Trash"), synonyms: "uninstall, remove app, delete app, leftovers, clean up, Trash, bin, watch, automatic, offer, notify"),
            SettingsItem(tab: .background, title: String(localized: "What runs in the background"), synonyms: "login items, open at login, launch agents, launch daemons, daemons, startup, autostart, helpers, running, services, leftovers, background, turn off"),
            SettingsItem(tab: .animations, title: String(localized: "Animation speed"), synonyms: "animations, motion, fast, faster, instant, speed up", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Delay before the Dock appears"), synonyms: "autohide, hide Dock, delay, wait", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "How fast the Dock slides out"), synonyms: "autohide, hide Dock, speed", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Minimize effect"), synonyms: "genie, scale, suck, minimize"),
            SettingsItem(tab: .animations, title: String(localized: "Bouncing icons"), synonyms: "bounce, jump, attention, Dock"),
            SettingsItem(tab: .animations, title: String(localized: "Opening windows"), synonyms: "window animation, new window, zoom", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Save dialogs and resizing"), synonyms: "sheet, save, print, resize, panel", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Quick Look"), synonyms: "preview, Space bar", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Columns in Finder"), synonyms: "column view, scroll", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Finder animations"), synonyms: "folder, Get Info, info window", directOnly: true),
            SettingsItem(tab: .animations, title: String(localized: "Even calmer: Reduce Motion in Accessibility"), synonyms: "reduce motion, accessibility, motion sickness"),
            SettingsItem(tab: .games, title: String(localized: "Game Mode"), synonyms: "game, games, gaming, play, Steam, full screen"),
            SettingsItem(tab: .games, title: String(localized: "The game doesn’t close"), synonyms: "quit, close, exit"),
            SettingsItem(tab: .games, title: String(localized: "The game window doesn’t close")),
            SettingsItem(tab: .games, title: String(localized: "Apps and windows don’t switch"), synonyms: "Command Tab, app switcher"),
            SettingsItem(tab: .games, title: String(localized: "The game doesn’t hide")),
            SettingsItem(tab: .games, title: String(localized: "Search doesn’t pop up"), synonyms: "Spotlight"),
            SettingsItem(tab: .games, title: String(localized: "Siri and voice typing don’t start")),
            SettingsItem(tab: .games, title: String(localized: "The app grid doesn’t open"), synonyms: "Launchpad"),
            SettingsItem(tab: .games, title: String(localized: "The view of all windows doesn’t open"), synonyms: "Mission Control, Spaces, Notification Center, Stage Manager"),
            SettingsItem(tab: .games, title: String(localized: "The view of the game’s windows doesn’t open"), synonyms: "App Exposé"),
            SettingsItem(tab: .games, title: String(localized: "The game doesn’t slide off the screen"), synonyms: "Show Desktop"),
            SettingsItem(tab: .games, title: String(localized: "Desktops don’t switch"), synonyms: "Spaces, swipe, gestures, trackpad"),
            SettingsItem(tab: .games, title: String(localized: "Desktops don’t switch by number"), synonyms: "Spaces, swipe, gestures, trackpad"),
            SettingsItem(tab: .games, title: String(localized: "Gestures don’t leave the game"), synonyms: "Spaces, swipe, pinch, gestures, trackpad, Magic Mouse, Mission Control, Notification Center"),
            SettingsItem(tab: .games, title: String(localized: "Emoji don’t open"), synonyms: "symbols, dictionary"),
            SettingsItem(tab: .games, title: String(localized: "The dictionary doesn’t pop up"), synonyms: "Look Up"),
            SettingsItem(tab: .games, title: String(localized: "The keyboard stays in the game"), synonyms: "keyboard focus, function keys, Control Space, Ctrl, Shift, Option, input source, language"),
            SettingsItem(tab: .games, title: String(localized: "🌐 shortcuts are paused"), synonyms: "fn, globe key"),
            SettingsItem(tab: .games, title: String(localized: "The wheel switches slots while you hold ⇧"), synonyms: "shift, scroll, wheel, hotbar, sneak, minecraft, mouse"),
            SettingsItem(tab: .games, title: String(localized: "⌃-click works as a plain click"), synonyms: "ctrl, control key, shortcuts, right-click, context menu"),
            SettingsItem(tab: .games, title: String(localized: "The pointer stays in the game"), synonyms: "mouse, cursor, Dock, menu bar, hot corners, edges, second display", directOnly: true),
            SettingsItem(tab: .games, title: String(localized: "The screen stays on")),
            SettingsItem(tab: .games, title: String(localized: "Your games")),
            SettingsItem(tab: .games, title: String(localized: "Show FPS"), synonyms: "frame rate, frames per second, counter, performance, lag, screen recording"),
            SettingsItem(tab: .games, title: String(localized: "Corner for FPS")),
            SettingsItem(tab: .games, title: String(localized: "System keyboard shortcuts")),
            SettingsItem(tab: .games, title: String(localized: "Game safeguards")),
            SettingsItem(tab: .pet, title: String(localized: "Pet on the desktop"), synonyms: "pet, buddy, friend, character, mascot, desktop, jump, Space"),
            SettingsItem(tab: .pet, title: String(localized: "Talks sometimes"), synonyms: PetTool.talksSynonyms),
            SettingsItem(tab: .pet, title: String(localized: "Follows your rhythm"), synonyms: "sleep, nap, doze, tired, energy, typing, away, idle, wake"),
            SettingsItem(tab: .pet, title: String(localized: "Ball"), synonyms: "toy, football, soccer, kick, play, throw, selection, platform"),
            SettingsItem(tab: .pet, title: String(localized: "Wardrobe"), synonyms: "clothes, outfit, costume, dress up, hats, glasses, scarf, shoes, cape, wings"),
            SettingsItem(tab: .pet, title: String(localized: "Looks"), synonyms: "outfit, costume, wizard, pirate, astronaut, superhero, cowboy, fairy, king, gentleman, scientist, detective"),
            SettingsItem(tab: .pet, title: String(localized: "Awards"), synonyms: "medals, achievements, trophies, badges, rewards, progress, unlock, earned"),
            SettingsItem(tab: .pet, title: String(localized: "Erase Progress…"), synonyms: "reset, delete, clear, start over, privacy"),
            SettingsItem(tab: .permissions, title: Permission.accessibilityTitle, synonyms: "privacy, security, access, accessibility, device control, data access"),
            SettingsItem(tab: .permissions, title: String(localized: "Input Monitoring"), synonyms: "privacy, security, access"),
            SettingsItem(tab: .permissions, title: String(localized: "Screen Recording"), synonyms: "privacy, security, access"),
            SettingsItem(tab: .permissions, title: String(localized: "iCloud Drive"), synonyms: "privacy, security, access", directOnly: true),
            SettingsItem(tab: .permissions, title: String(localized: "Finder Extensions"), synonyms: "privacy, security, access, right-click, menu, extension"),
            SettingsItem(tab: .permissions, title: String(localized: "Full Disk Access"), synonyms: "privacy, security, access, files, disk", directOnly: true),
            SettingsItem(tab: .permissions, title: String(localized: "Left by deleted apps"), synonyms: "permissions, privacy, deleted apps, cleanup, tcc"),
            SettingsItem(tab: .about, title: String(localized: "Check for updates automatically"), synonyms: "update, new version, software update", directOnly: true),
            SettingsItem(tab: .about, title: String(localized: "What’s New"), synonyms: "changelog, release notes, version"),
            SettingsItem(tab: .about, title: String(localized: "Report a Problem"), synonyms: "bug, issue, feedback, support"),
            SettingsItem(tab: .about, title: String(localized: "License (MIT)"), synonyms: "open source, legal"),
            SettingsItem(tab: .about, title: String(localized: "Buy me a coffee"), synonyms: "support, donate, donation, tip, sponsor, thanks", directOnly: true),
            SettingsItem(tab: .about, title: "GitHub", synonyms: "open source, legal"),
        ] + (SettingsTab.sound.isAvailable ? [
            SettingsItem(tab: .permissions, title: String(localized: "System Audio Recording"), synonyms: "privacy, security, access"),
        ] : []) + GameShortcutGroup.allCases.map { SettingsItem(tab: .games, title: $0.title, synonyms: $0.detail) }
    }

    func matches(_ query: String) -> Bool {
        let words = synonyms + ", " + Bundle.main.localizedString(forKey: synonyms, value: nil, table: nil)
        return (target == nil || SettingsSearch.matchesKeys(query, keys: keys)) && SettingsSearch.matches(query, fields: [title, words, tab.title, keys])
    }
}
