import Foundation

enum AppConstants {
    static let appName = "pikapik"
    static let bundleIDPrefix = "com.pikapik.app"
    static let directBundleID = "com.pikapik.app.direct"
    static let appStoreBundleID = "com.pikapik.app"
    static let devBundleID = "com.pikapik.app.dev"

    static let finderBundleID = "com.apple.finder"
    static let dockBundleID = "com.apple.dock"
    static let systemSettingsBundleID = "com.apple.systempreferences"
    static let symbolicHotKeysDomain = "com.apple.symbolichotkeys"
    static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"
    static let bluetoothTrackpadDomain = "com.apple.driver.AppleBluetoothMultitouch.trackpad"

    static let githubRepoURL = "https://github.com/dev-pikapik/pikapik"
    static let githubReleasesURL = URL(string: "https://github.com/dev-pikapik/pikapik/releases/latest")!
    static let buyMeACoffeeURL = "https://buymeacoffee.com/pikapik"
    static let appleMacRepairURL = URL(string: "https://support.apple.com/mac/repair")!
}

enum ToolID {
    static let keepAwake = "keep-awake"
    static let displayOff = "display-off"
    static let brightness = "brightness"
    static let brightnessKeys = "brightness-keys"
    static let fans = "fans"
    static let temperatures = "temperatures"
    static let speedTest = "speed-test"
    static let appVolume = "app-volume"
    static let inputSwitch = "input-switch"
    static let keyRepeat = "key-repeat"
    static let homeEnd = "home-end"
    static let layoutFix = "layout-fix"
    static let linearPointer = "linear-pointer"
    static let wheelLines = "wheel-lines"
    static let wheelDirection = "wheel-direction"
    static let sideButtons = "side-buttons"
    static let hideApp = "hide-app"
    static let middleClick = "middle-click"
    static let windowZoom = "window-zoom"
    static let commandKeys = "command-keys"
    static let quitOnClose = "quit-on-close"
    static let dockHide = "dock-hide"
    static let dockDisplay = "dock-display"
    static let displayScale = "display-scale"
    static let newFile = "new-file"
    static let compress = "compress"
    static let convert = "convert"
    static let archive = "archive"
    static let finderOpen = "finder-open"
    static let finderCut = "finder-cut"
    static let finderDelete = "finder-delete"
    static let desktopIcons = "desktop-icons"
    static let hiddenFiles = "hidden-files"
    static let animations = "animations"
    static let gameMode = "game-mode"
    static let pet = "pet"
    static let trashWatch = "uninstaller-trash-watch"
    static let appsCanAsk = "apps-can-ask"
}

enum PreferenceKey {
    static let appearance = "appearance"
    static let appleLanguages = "AppleLanguages"
    static let openAtLogin = "open-at-login"
    static let keepRunning = "keep-running"
    static let checkUpdates = "check-updates"
    static let quickHidden = "quick-hidden"
    static let launchMaintenance = "launch-maintenance"

    static let commandKeysQuit = "command-keys-quit"
    static let commandKeysClose = "command-keys-close"
    static let commandKeysQuitShortcut = "command-keys-quit-shortcut"
    static let commandKeysCloseShortcut = "command-keys-close-shortcut"

    static let homeEndExcluded = "home-end-excluded"
    static let layoutFixAuto = "layout-fix-auto"
    static let layoutFixShortcut = "layout-fix-shortcut"
    static let layoutFixExcluded = "layout-fix-excluded"
    static let layoutFixIgnored = "layout-fix-ignored"

    static let keyRepeatSaved = "key-repeat-saved"
    static let chromiumAXJournal = "chromium-accessibility-original"

    static let linearPointerSpeed = "linear-pointer-speed"
    static let linearPointerSaved = "linear-pointer-saved"
    static let linearPointerOurs = "linear-pointer-ours"
    static let wheelLinesCount = "wheel-lines-count"
    static let wheelLinesMode = "wheel-lines-mode"
    static let wheelLinesPixels = "wheel-lines-pixels"
    static let wheelDirectionNatural = "wheel-direction-natural"
    static let wheelDirectionTrackpadNatural = "wheel-direction-trackpad-natural"
    static let sideButtonsSwap = "side-buttons-swap"
    static let hideAppButton = "hide-app-button"
    static let middleClickFingers = "middle-click-fingers"

    static let quitOnCloseExcluded = "quit-on-close-excluded"
    static let dockHideAction = "dock-hide-action"
    static let windowZoomExcluded = "window-zoom-excluded"

    static let archiveFormat = "archive-format"
    static let archiveSplit = "archive-split"

    static let gameModeGames = "game-mode-games"
    static let gameModeNotGames = "game-mode-not-games"
    static let gameModeSystemShortcuts = "game-mode-system-shortcuts"
    static let gameModeFrameRate = "game-mode-fps"
    static let gameModeFrameRateCorner = "game-mode-fps-corner"
    static let gameModeFrameRateRecording = "game-mode-fps-recording"
    static let gameModeHotKeysOff = "game-mode-hotkeys-off"
    static let gameModeDock = "game-mode-dock"

    static let keepAwakeMode = "keep-awake-mode"
    static let keepAwakeDuration = "keep-awake-duration"
    static let keepAwakeDisplay = "keep-awake-display"
    static let keepAwakeLid = "keep-awake-lid"
    static let keepAwakeBattery = "keep-awake-battery"

    static let displayScale = "display-scale"

    static let fansRPM = "fans-rpm"
    static let speedTestResult = "speed-test-result"

    static let backgroundTurnedOffLogins = "background-turned-off-logins"
    static let backgroundTurnedOffAgents = "background-turned-off-agents"
    static let backgroundTurnedOffServices = "background-turned-off-services"

    static let systemAudioGranted = "system-audio-granted"
    static let systemAudioAsked = "system-audio-asked"

    static let animationsSpeed = "animations-speed"
    static let animationsDockDelay = "animations-dock-delay"
    static let animationsDockSpeed = "animations-dock-speed"
    static let animationsMinimize = "animations-minimize"
    static let animationsBounce = "animations-bounce"
    static let animationsWindowOpen = "animations-window-open"
    static let animationsResize = "animations-resize"
    static let animationsQuickLook = "animations-quick-look"
    static let animationsFinderColumns = "animations-finder-columns"
    static let animationsFinder = "animations-finder"

    static let petTalks = "pet-talks"
    static let petRhythm = "pet-rhythm"
    static let petBall = "pet-ball"
    static let petCounts = "pet-counts"
    static let petAwards = "pet-awards"
    static let petSeen = "pet-seen"
    static let petFresh = "pet-fresh"
    static let petOutfit = "pet-outfit"

    static let appVolumeLevels = "app-volume-levels"
    static let appVolumeMuted = "app-volume-muted"
    static let appVolumeNames = "app-volume-names"

    static let newMarksVersion = "new-marks-version"
    static let newMarksFrom = "new-marks-from"
    static let newMarksSince = "new-marks-since"
    static let newMarksSeen = "new-marks-seen"
}

enum SystemPath {
    static let tar = "/usr/bin/tar"
    static let ditto = "/usr/bin/ditto"
    static let pluginkit = "/usr/bin/pluginkit"
    static let killall = "/usr/bin/killall"
    static let caffeinate = "/usr/bin/caffeinate"
    static let pmset = "/usr/bin/pmset"
    static let codesign = "/usr/bin/codesign"
    static let printf = "/usr/bin/printf"
    static let tccutil = "/usr/bin/tccutil"
    static let metalperftrace = "/usr/bin/metalperftrace"
    static let networkQuality = "/usr/bin/networkQuality"

    static let systemProfiler = "/usr/sbin/system_profiler"
    static let chown = "/usr/sbin/chown"
    static let pkgutil = "/usr/sbin/pkgutil"

    static let launchctl = "/bin/launchctl"
    static let mkdir = "/bin/mkdir"
    static let rm = "/bin/rm"
    static let cp = "/bin/cp"
    static let chmod = "/bin/chmod"
    static let sh = "/bin/sh"
    static let bash = "/bin/bash"
    static let sleep = "/bin/sleep"
    static let standardBinPath = "/usr/bin:/bin"

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let displayServicesFramework = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    static let skyLightFramework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    static let ioKitFramework = "/System/Library/Frameworks/IOKit.framework/IOKit"
    static let applicationServicesFramework = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

    static let keyboardSettingsExtension = "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex"
    static let accessibilitySettingsExtension = "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
    static let desktopSettingsExtension = "/System/Library/ExtensionKit/Extensions/DesktopSettings.appex"
    static let trackpadExtension = "/System/Library/ExtensionKit/Extensions/TrackpadExtension.appex"
    static let mouseExtension = "/System/Library/ExtensionKit/Extensions/MouseExtension.appex"

    static let systemSettingsApp = "/System/Applications/System Settings.app"
    static let shortcutsApp = "/System/Applications/Shortcuts.app"
    static let activityMonitorApp = "/System/Applications/Utilities/Activity Monitor.app"
    static let finderApp = "/System/Library/CoreServices/Finder.app"

    static let applications = "/Applications"
    static let systemApplications = "/System/Applications"
    static let privilegedHelperToolsDir = "/Library/PrivilegedHelperTools"
    static let systemTCCDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"

    static let homebrewPrefixes = ["/opt/homebrew", "/usr/local"]
    static let homebrewCaskrooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
}

enum SystemPane {
    static let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    static let mouse = "x-apple.systempreferences:com.apple.Mouse-Settings.extension"
    static let battery = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!
    static let displays = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!
}
