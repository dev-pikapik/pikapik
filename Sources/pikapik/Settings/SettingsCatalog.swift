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
                     synonyms: [entry.rawName, entry.sectionName, entry.group.title, entry.group.detail, entry.description.text, entry.supportsBackground ? SettingTitle.switchLanguage + ", Switch language" : "", "game games gaming", String(entry.id)].joined(separator: ", "),
                     target: entry.anchor, detail: [entry.group.title, entry.text ?? (entry.pointer == nil ? String(localized: "No key assigned") : entry.pointer?.detail)].compactMap { $0 }.joined(separator: " · "), keys: entry.text ?? "")
    }

    static var all: [SettingsItem] {
        #if APPSTORE
        let hasArchives = ToolRegistry.shared.tools.contains { $0 is ArchiveTool }
        return allItems.filter {
            $0.tab.isAvailable && !$0.directOnly
                && (SettingsSync.isAvailable || $0.id != SettingTitle.syncWithICloud)
                && (hasArchives || $0.id != SettingTitle.archivesInFinder)
        } + [
            SettingsItem(tab: .animations, title: SettingTitle.hideDockAutomatically, synonyms: "autohide, hide Dock, delay, wait"),
            SettingsItem(tab: .keyboard, title: SettingTitle.fixSelectedText, synonyms: "shortcut, undo, convert, selection, layout"),
            SettingsItem(tab: .permissions, title: SettingTitle.folders, synonyms: "privacy, security, access, files, save, home"),
            SettingsItem(tab: .about, title: SettingTitle.sayThanks, synonyms: "support, donate, donation, tip, sponsor, thanks"),
        ] + Permissions.privacyLists.map {
            SettingsItem(tab: .permissions, title: $0.title, target: $0.pane, detail: SettingTitle.otherAppsPermissions)
        }
        #else
        return allItems.filter { $0.tab.isAvailable }
        #endif
    }

    private static var allItems: [SettingsItem] {
        [
            SettingsItem(tab: .general, title: SettingTitle.openAtLogin, synonyms: "launch, startup, autostart, login items"),
            SettingsItem(tab: .general, title: SettingTitle.stayInBackground, synonyms: "background, quit, close, exit, hide, menu bar icon, option", directOnly: true),
            SettingsItem(tab: .general, title: SettingTitle.appearance, synonyms: "theme, dark mode, light mode, colors"),
            SettingsItem(tab: .general, title: SettingTitle.language, synonyms: "localization, translation"),
            SettingsItem(tab: .general, title: SettingTitle.settingsFile, synonyms: "backup, export, import, restore, JSON"),
            SettingsItem(tab: .general, title: SettingTitle.syncWithICloud, synonyms: "iCloud Drive, another Mac, backup"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.keepMacAwake, synonyms: "sleep, caffeine, insomnia"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.duration, synonyms: "time, timer, days, hours, minutes, seconds"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.display, synonyms: "screen, monitor, dim, screen saver"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.turnOffDisplayNow, synonyms: "screen, monitor, dim, screen saver"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.controlCenterButtons, synonyms: "widget, Control Center, Shortcuts, menu bar, button"),
        ] + (KeepAwake.shared.hasLid ? [
            SettingsItem(tab: .keepAwake, title: SettingTitle.workWithLidClosed, synonyms: "clamshell, laptop, MacBook, external display"),
            SettingsItem(tab: .keepAwake, title: SettingTitle.stopOnLowBattery, synonyms: "battery, power, charge"),
        ] : []) + [
            SettingsItem(tab: .brightness, title: SettingTitle.brightness, synonyms: "monitor, display, screen, external display, dim, dimmer, brighter, darker, DDC, backlight"),
            SettingsItem(tab: .brightness, title: SettingTitle.brightnessKeys, synonyms: "keyboard, F1, F2, brightness up, brightness down, keys, monitor, display"),
            SettingsItem(tab: .brightness, title: SettingTitle.dimPictureInstead, synonyms: "gamma, dim, darker, software dimming, monitor, display, screen", directOnly: true),
            SettingsItem(tab: .battery, title: SettingTitle.batteryHealth, synonyms: "battery, condition, maximum capacity, cycle count, cycles, wear, service, replace"),
            SettingsItem(tab: .battery, title: SettingTitle.powerAdapter, synonyms: "charger, charging, watts, power use, adapter, plug"),
            SettingsItem(tab: .battery, title: SettingTitle.keepItHealthy, synonyms: "charge limit, 80%, optimized battery charging, charging on hold, heat, temperature, storage, tips"),
            SettingsItem(tab: .fans, title: SettingTitle.fanSpeed, synonyms: "fan, rpm, cooling, cooler, hot, heat, noise, quiet, loud, temperature, thermal"),
            SettingsItem(tab: .permissions, title: SettingTitle.administratorAccess, synonyms: "allow, helper, password, administrator, install, remove", directOnly: true),
            SettingsItem(tab: .temperatures, title: SettingTitle.temperature, synonyms: "heat, hot, warm, thermal, sensors, CPU, GPU, processor, graphics, memory, RAM, SSD, storage, battery, Wi-Fi, degrees, Celsius, Fahrenheit, overheating"),
        ] + speedTestItems + [
            SettingsItem(tab: .ports, title: SettingTitle.freeAPort, synonyms: "port, server, localhost, listen, kill, lsof, address in use, EADDRINUSE, process, 3000, 8080, 5000, AirPlay"),
            SettingsItem(tab: .sound, title: SettingTitle.appVolume, synonyms: "mixer, mute app, per-app volume, volume, sound, audio, quiet, loud"),
            SettingsItem(tab: .keyboard, title: SettingTitle.switchLanguage, synonyms: "keyboard layout, input source, option, shift, alt"),
            SettingsItem(tab: .keyboard, title: SettingTitle.repeatHeldKey, synonyms: "key repeat, hold, accent menu, games, typing", directOnly: true),
            SettingsItem(tab: .keyboard, title: SettingTitle.homeAndEnd, synonyms: "home, end, line, cursor, beginning, select, text, typing"),
            SettingsItem(tab: .keyboard, title: SettingTitle.homeAndEndExcluded, synonyms: "exceptions, exclude, list, terminal, virtual machine, remote desktop"),
            SettingsItem(tab: .keyboard, title: SettingTitle.retypeWrongLanguage, synonyms: "wrong layout, keyboard layout, language, switch, convert, typo, gibberish, Services"),
            SettingsItem(tab: .keyboard, title: SettingTitle.fixWordsAsYouType, synonyms: "automatic, auto, Space, Return, layout", directOnly: true),
            SettingsItem(tab: .keyboard, title: SettingTitle.fixLastWordOrSelection, synonyms: "shortcut, undo, convert, selection, layout", directOnly: true),
            SettingsItem(tab: .keyboard, title: SettingTitle.layoutFixExcluded, synonyms: "exceptions, exclude, list, layout", directOnly: true),
            SettingsItem(tab: .mouse, title: SettingTitle.turnOffPointerAcceleration, synonyms: "linear, mouse acceleration, sensitivity"),
            SettingsItem(tab: .mouse, title: SettingTitle.trackingSpeed, synonyms: "pointer speed, sensitivity, fast, slow", directOnly: true),
            SettingsItem(tab: .mouse, title: SettingTitle.scrollByLines, synonyms: "wheel, scrolling speed, acceleration"),
            SettingsItem(tab: .mouse, title: SettingTitle.distancePerClick, synonyms: "scrolling speed, wheel, notch"),
            SettingsItem(tab: .mouse, title: SettingTitle.scrollBy, synonyms: "pixels, lines, wheel, games, scrolling mode, notch"),
            SettingsItem(tab: .mouse, title: SettingTitle.scrollDirection, synonyms: "natural scrolling, classic, reverse, invert, Universal Control, trackpad, mouse, Magic Mouse, wheel, direction"),
            SettingsItem(tab: .mouse, title: SettingTitle.trackpadDirection, synonyms: "natural, classic, reverse, invert, trackpad, two fingers, Magic Mouse, up, down"),
            SettingsItem(tab: .mouse, title: SettingTitle.mouseWheelDirection, synonyms: "natural, classic, reverse, invert, wheel, up, down"),
            SettingsItem(tab: .mouse, title: SettingTitle.sideButtons, synonyms: "buttons 4 and 5, browser, navigation, thumb buttons"),
            SettingsItem(tab: .mouse, title: SettingTitle.swapSideButtons, synonyms: "reverse, back, forward"),
            SettingsItem(tab: .mouse, title: SettingTitle.mouseButtonHidesApp, synonyms: "hide, ⌘H, cmd H, middle button, button 4, button 5, mouse button"),
            SettingsItem(tab: .mouse, title: SettingTitle.middleClickTrackpad, synonyms: "middle button, wheel click, three fingers, four fingers, tap, open link in new tab, close tab", directOnly: true),
            SettingsItem(tab: .mouse, title: SettingTitle.fingers, synonyms: "middle click, three, four, tap, click, trackpad", directOnly: true),
            SettingsItem(tab: .windows, title: SettingTitle.greenButtonEnlargesWindow, synonyms: "zoom, maximize, full screen, green button, option click", directOnly: true),
            SettingsItem(tab: .windows, title: SettingTitle.greenButtonExcluded, synonyms: "exceptions, exclude, list", directOnly: true),
            SettingsItem(tab: .windows, title: SettingTitle.protectQuittingAndClosing, synonyms: "quit, close, command, accidental, shortcut"),
            SettingsItem(tab: .windows, title: SettingTitle.quitApp, synonyms: "change shortcut, record keys, Command Shift Q"),
            SettingsItem(tab: .windows, title: SettingTitle.closeWindow, synonyms: "change shortcut, record keys, Command Shift W"),
            SettingsItem(tab: .windows, title: SettingTitle.quitWhenLastWindowCloses, synonyms: "close button, red button, terminate, exit", directOnly: true),
            SettingsItem(tab: .windows, title: SettingTitle.neverQuitApps, synonyms: "exceptions, exclude, list", directOnly: true),
            SettingsItem(tab: .dock, title: SettingTitle.dockClickMinimizeOrHide, synonyms: "Dock, minimize, hide, taskbar", directOnly: true),
            SettingsItem(tab: .dock, title: SettingTitle.dockClickAction, synonyms: "Dock, minimize, hide, taskbar", directOnly: true),
            SettingsItem(tab: .dock, title: SettingTitle.keepDockOnOneDisplay, synonyms: "Dock, display, monitor, screen, jump, move"),
            SettingsItem(tab: .dock, title: SettingTitle.mainDisplay, synonyms: "primary, main screen, Displays settings"),
            SettingsItem(tab: .finder, title: SettingTitle.newFileInFinder, synonyms: "create, text file, txt, right-click, context menu, Desktop"),
            SettingsItem(tab: .finder, title: SettingTitle.smallerCopyInFinder, synonyms: "compress, shrink, smaller, reduce size, optimize, image, photo, picture, video, audio, music, PNG, JPEG, JPG, HEIC, TIFF, PDF, GIF, MP4, MOV, M4A, WAV, AIFF, TinyPNG"),
            SettingsItem(tab: .finder, title: SettingTitle.convertInFinder, synonyms: "convert, format, export, save as, image, photo, picture, video, audio, music, PNG, JPEG, JPG, HEIC, TIFF, PDF, GIF, MP4, MOV, M4A, WAV, AIFF"),
            SettingsItem(tab: .finder, title: SettingTitle.archivesInFinder, synonyms: "archive, extract, unzip, unpack, zip, rar, 7z, tar, password, split, right-click, context menu"),
            SettingsItem(tab: .finder, title: SettingTitle.openArchivesInPikapik, synonyms: "archive, default app, open with, double-click, unzip, zip, 7z", directOnly: true),
            SettingsItem(tab: .finder, title: SettingTitle.enterOpensFiles, synonyms: "return, enter, open, rename, F2, keyboard", directOnly: true),
            SettingsItem(tab: .finder, title: SettingTitle.cutFilesInFinder, synonyms: "cut, paste, move, files, folders, command X"),
            SettingsItem(tab: .finder, title: SettingTitle.deleteRemovesFiles, synonyms: "delete, backspace, trash, remove, files, folders, keyboard", directOnly: true),
            SettingsItem(tab: .finder, title: SettingTitle.hideDesktopIcons, synonyms: "desktop, icons, files, folders, clean, hide, presentation, screen sharing, recording, screenshot, Stage Manager"),
            SettingsItem(tab: .finder, title: SettingTitle.showHiddenFiles, synonyms: "hidden, invisible, dot files, system files, Library, show all files, Command Shift Period"),
            SettingsItem(tab: .player, title: SettingTitle.openVideo, synonyms: "video, movie, film, watch, play, mkv, avi, wmv, webm, flv"),
            SettingsItem(tab: .player, title: SettingTitle.openVideosInPikapik, synonyms: "default app, open with, double-click, video, movie, mkv, avi, webm, mp4, mov, QuickTime"),
            SettingsItem(tab: .player, title: SettingTitle.openMusicInPikapik, synonyms: "music, song, audio, flac, mp3, ogg, opus, wma, default app, open with, double-click"),
            SettingsItem(tab: .player, title: SettingTitle.openPicturesInPikapik, synonyms: "photo, image, picture, jpeg, jpg, png, heic, webp, avif, gif, raw, psd, tiff, svg, default app, open with, double-click, Preview"),
            SettingsItem(tab: .player, title: SettingTitle.playerLicenses, synonyms: "open source, legal, FFmpeg, dav1d, libass, FreeType, HarfBuzz, FriBidi"),
            SettingsItem(tab: .uninstaller, title: SettingTitle.removeAnApp, synonyms: "uninstall, remove app, delete app, delete, remove, app, application, cleaner, clean up, leftovers, trash, reset, put back, restore, undo"),
            SettingsItem(tab: .uninstaller, title: SettingTitle.offerCleanupOnTrash, synonyms: "uninstall, remove app, delete app, leftovers, clean up, Trash, bin, watch, automatic, offer, notify"),
            SettingsItem(tab: .background, title: SettingTitle.whatRunsInBackground, synonyms: "login items, open at login, launch agents, launch daemons, daemons, startup, autostart, helpers, running, services, leftovers, background, turn off"),
            SettingsItem(tab: .animations, title: SettingTitle.animationSpeed, synonyms: "animations, motion, fast, faster, instant, speed up", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.dockAppearDelay, synonyms: "autohide, hide Dock, delay, wait", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.dockSlideSpeed, synonyms: "autohide, hide Dock, speed", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.minimizeEffect, synonyms: "genie, scale, suck, minimize"),
            SettingsItem(tab: .animations, title: SettingTitle.bouncingIcons, synonyms: "bounce, jump, attention, Dock"),
            SettingsItem(tab: .animations, title: SettingTitle.openingWindows, synonyms: "window animation, new window, zoom", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.saveDialogsAndResizing, synonyms: "sheet, save, print, resize, panel", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.quickLook, synonyms: "preview, Space bar", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.columnsInFinder, synonyms: "column view, scroll", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.finderAnimations, synonyms: "folder, Get Info, info window", directOnly: true),
            SettingsItem(tab: .animations, title: SettingTitle.reduceMotionInAccessibility, synonyms: "reduce motion, accessibility, motion sickness"),
            SettingsItem(tab: .games, title: SettingTitle.gameMode, synonyms: "game, games, gaming, play, Steam, full screen"),
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
            SettingsItem(tab: .games, title: SettingTitle.yourGames),
            SettingsItem(tab: .games, title: SettingTitle.showFPS, synonyms: "frame rate, frames per second, counter, performance, lag, screen recording"),
            SettingsItem(tab: .games, title: SettingTitle.cornerForFPS),
            SettingsItem(tab: .games, title: SettingTitle.systemKeyboardShortcuts),
            SettingsItem(tab: .games, title: SettingTitle.gameSafeguards),
            SettingsItem(tab: .pet, title: SettingTitle.petOnDesktop, synonyms: "pet, buddy, friend, character, mascot, desktop, jump, Space"),
            SettingsItem(tab: .pet, title: SettingTitle.talksSometimes, synonyms: PetTool.talksSynonyms),
            SettingsItem(tab: .pet, title: SettingTitle.followsYourRhythm, synonyms: "sleep, nap, doze, tired, energy, typing, away, idle, wake"),
            SettingsItem(tab: .pet, title: SettingTitle.ball, synonyms: "toy, football, soccer, kick, play, throw, selection, platform"),
            SettingsItem(tab: .pet, title: SettingTitle.wardrobe, synonyms: "clothes, outfit, costume, dress up, hats, glasses, scarf, shoes, cape, wings"),
            SettingsItem(tab: .pet, title: SettingTitle.looks, synonyms: "outfit, costume, wizard, pirate, astronaut, superhero, cowboy, fairy, king, gentleman, scientist, detective"),
            SettingsItem(tab: .pet, title: SettingTitle.awards, synonyms: "medals, achievements, trophies, badges, rewards, progress, unlock, earned"),
            SettingsItem(tab: .pet, title: SettingTitle.eraseProgress, synonyms: "reset, delete, clear, start over, privacy"),
            SettingsItem(tab: .permissions, title: Permission.accessibilityTitle, synonyms: "privacy, security, access, accessibility, device control, data access"),
            SettingsItem(tab: .permissions, title: SettingTitle.inputMonitoring, synonyms: "privacy, security, access"),
            SettingsItem(tab: .permissions, title: SettingTitle.screenRecording, synonyms: "privacy, security, access"),
            SettingsItem(tab: .permissions, title: SettingTitle.iCloudDrive, synonyms: "privacy, security, access", directOnly: true),
            SettingsItem(tab: .permissions, title: SettingTitle.finderExtensions, synonyms: "privacy, security, access, right-click, menu, extension"),
            SettingsItem(tab: .permissions, title: SettingTitle.fullDiskAccess, synonyms: "privacy, security, access, files, disk", directOnly: true),
            SettingsItem(tab: .permissions, title: SettingTitle.leftByDeletedApps, synonyms: "permissions, privacy, deleted apps, cleanup, tcc"),
            SettingsItem(tab: .about, title: SettingTitle.checkForUpdatesAutomatically, synonyms: "update, new version, software update", directOnly: true),
            SettingsItem(tab: .about, title: SettingTitle.whatsNew, synonyms: "changelog, release notes, version"),
            SettingsItem(tab: .about, title: SettingTitle.reportAProblem, synonyms: "bug, issue, feedback, support"),
            SettingsItem(tab: .about, title: SettingTitle.licenseMIT, synonyms: "open source, legal"),
            SettingsItem(tab: .about, title: SettingTitle.buyMeACoffee, synonyms: "support, donate, donation, tip, sponsor, thanks", directOnly: true),
            SettingsItem(tab: .about, title: "GitHub", synonyms: "open source, legal"),
        ] + (SettingsTab.sound.isAvailable ? [
            SettingsItem(tab: .permissions, title: SettingTitle.systemAudioRecording, synonyms: "privacy, security, access"),
        ] : []) + GameShortcutGroup.allCases.map { SettingsItem(tab: .games, title: $0.title, synonyms: $0.detail) }
    }

    private static var speedTestItems: [SettingsItem] {
        #if APPSTORE
        []
        #else
        [
            SettingsItem(tab: .speedTest, title: SettingTitle.checkSpeed, synonyms: "internet, Wi-Fi, network, bandwidth, ping, Mbps, speedtest"),
            SettingsItem(tab: .speedTest, title: SettingTitle.whatItsGoodFor, synonyms: "4K, video, calls, games, downloads"),
        ]
        #endif
    }

    func matches(_ query: String) -> Bool {
        let words = synonyms + ", " + Bundle.main.localizedString(forKey: synonyms, value: nil, table: nil)
        return (target == nil || SettingsSearch.matchesKeys(query, keys: keys)) && SettingsSearch.matches(query, fields: [title, words, tab.title, keys])
    }
}
