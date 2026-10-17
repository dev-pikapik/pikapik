import Foundation

enum TabTitle {
    static var general: String { String(localized: "General") }
    static var battery: String { String(localized: "Battery") }
    static var keepAwake: String { String(localized: "Keep Awake") }
    static var brightness: String { String(localized: "Brightness") }
    static var fans: String { String(localized: "Fans") }
    static var temperatures: String { String(localized: "Temperature") }
    static var speedTest: String { String(localized: "Speed Test") }
    static var ports: String { String(localized: "Ports") }
    static var sound: String { String(localized: "Sound") }
    static var keyboard: String { String(localized: "Keyboard") }
    static var mouse: String { String(localized: "Mouse") }
    static var windows: String { String(localized: "Windows") }
    static var dock: String { String(localized: "Dock") }
    static var finder: String { String(localized: "Finder") }
    static var animations: String { String(localized: "Animations") }
    static var player: String { String(localized: "Player") }
    static var uninstaller: String { String(localized: "Uninstaller") }
    static var background: String { String(localized: "Background Tasks") }
    static var games: String { String(localized: "Games") }
    static var pet: String { String(localized: "Pet") }
    static var permissions: String { String(localized: "Permissions") }
    static var about: String { String(localized: "About") }
}

enum SettingTitle {
    // General
    static var openAtLogin: String { String(localized: "Open at Login") }
    static var stayInBackground: String { String(localized: "Stay in the background after Quit") }
    static var appearance: String { String(localized: "Appearance") }
    static var language: String { String(localized: "Language") }
    static var settingsFile: String { String(localized: "Settings file") }
    static var syncWithICloud: String { String(localized: "Sync settings with iCloud") }

    // Keep Awake
    static var keepMacAwake: String { String(localized: "Keep your Mac awake") }
    static var duration: String { String(localized: "Duration") }
    static var display: String { String(localized: "Display") }
    static var turnOffDisplayNow: String { String(localized: "Turn off the display now") }
    static var controlCenterButtons: String { String(localized: "Buttons in Control Center and widgets") }
    static var workWithLidClosed: String { String(localized: "Work with the lid closed") }
    static var stopOnLowBattery: String { String(localized: "Stop when battery is below \(0.2.formatted(.percent))") }

    // Brightness
    static var brightness: String { String(localized: "Brightness") }
    static var brightnessKeys: String { String(localized: "Brightness keys") }
    static var dimPictureInstead: String { String(localized: "Dim the picture instead") }

    // Battery, Fans & Temperature
    static var batteryHealth: String { String(localized: "Battery Health") }
    static var powerAdapter: String { String(localized: "Power Adapter") }
    static var keepItHealthy: String { String(localized: "Keep It Healthy") }
    static var fanSpeed: String { String(localized: "Fan speed") }
    static var temperature: String { String(localized: "Temperature") }

    // Speed Test, Ports & Sound
    static var checkSpeed: String { String(localized: "Check Speed") }
    static var whatItsGoodFor: String { String(localized: "What it’s good for") }
    static var freeAPort: String { String(localized: "Free a port") }
    static var appVolume: String { String(localized: "App Volume") }

    // Keyboard
    static var switchLanguage: String { String(localized: "Switch language") }
    static var inputSwitch: String { switchLanguage }
    static var repeatHeldKey: String { String(localized: "Repeat a held key") }
    static var keyRepeat: String { repeatHeldKey }
    static var homeAndEnd: String { String(localized: "Home and End go to the start and end of a line") }
    static var homeEnd: String { homeAndEnd }
    static var homeAndEndExcluded: String { String(localized: "Home and End work as usual in these apps") }
    static var retypeWrongLanguage: String { String(localized: "Retype words you typed in the wrong language") }
    static var layoutFix: String { retypeWrongLanguage }
    static var fixWordsAsYouType: String { String(localized: "Fix words as you type") }
    static var fixLastWordOrSelection: String { String(localized: "Fix the last word or selected text") }
    static var fixLastWordOrSelectedText: String { fixLastWordOrSelection }
    static var fixSelectedText: String { String(localized: "Fix the selected text") }
    static var layoutFixExcluded: String { String(localized: "Don’t fix text in these apps") }

    // Mouse & Trackpad
    static var turnOffPointerAcceleration: String { String(localized: "Turn off pointer acceleration") }
    static var linearPointer: String { turnOffPointerAcceleration }
    static var trackingSpeed: String { String(localized: "Tracking speed") }
    static var scrollByLines: String { String(localized: "Scroll by lines") }
    static var wheelLines: String { scrollByLines }
    static var distancePerClick: String { String(localized: "Distance per click") }
    static var scrollBy: String { String(localized: "Scroll by") }
    static var scrollDirection: String { String(localized: "Scroll direction for trackpad and mouse") }
    static var wheelDirection: String { scrollDirection }
    static var trackpadDirection: String { String(localized: "Trackpad direction") }
    static var mouseWheelDirection: String { String(localized: "Mouse wheel direction") }
    static var sideButtons: String { String(localized: "Side buttons go back and forward") }
    static var swapSideButtons: String { String(localized: "Swap the side buttons") }
    static var mouseButtonHidesApp: String { String(localized: "Mouse button hides the current app") }
    static var hideApp: String { mouseButtonHidesApp }
    static var middleClickTrackpad: String { String(localized: "Middle click on the trackpad") }
    static var middleClick: String { middleClickTrackpad }
    static var fingers: String { String(localized: "Fingers") }

    // Windows & Dock
    static var greenButtonEnlargesWindow: String { String(localized: "Green button enlarges the window") }
    static var windowZoom: String { greenButtonEnlargesWindow }
    static var greenButtonExcluded: String { String(localized: "Green button works as usual in these apps") }
    static var protectQuittingAndClosing: String { String(localized: "Protect quitting and closing") }
    static var commandKeys: String { protectQuittingAndClosing }
    static var quitApp: String { String(localized: "Quit app") }
    static var closeWindow: String { String(localized: "Close window") }
    static var quitWhenLastWindowCloses: String { String(localized: "Quit when the last window closes") }
    static var quitOnClose: String { quitWhenLastWindowCloses }
    static var neverQuitApps: String { String(localized: "Never quit these apps") }
    static var dockClickMinimizeOrHide: String { String(localized: "Minimize or hide with a click in the Dock") }
    static var dockHide: String { dockClickMinimizeOrHide }
    static var dockClickAction: String { String(localized: "A click on the icon") }
    static var keepDockOnOneDisplay: String { String(localized: "Keep the Dock on one display") }
    static var dockDisplay: String { keepDockOnOneDisplay }
    static var mainDisplay: String { String(localized: "Main display") }

    // Finder
    static var newFileInFinder: String { String(localized: "New File in Finder") }
    static var smallerCopyInFinder: String { String(localized: "Smaller Copy in Finder") }
    static var convertInFinder: String { String(localized: "Convert in Finder") }
    static var archivesInFinder: String { String(localized: "Archives in Finder") }
    static var openArchivesInPikapik: String { String(localized: "Open archives in pikapik") }
    static var enterOpensFiles: String { String(localized: "Enter opens files in Finder") }
    static var cutFilesInFinder: String { String(localized: "Cut files in Finder") }
    static var deleteRemovesFiles: String { String(localized: "Delete removes files in Finder") }
    static var hideDesktopIcons: String { String(localized: "Hide desktop icons") }
    static var showHiddenFiles: String { String(localized: "Show hidden files") }

    // Player, Uninstaller & Background
    static var openVideo: String { String(localized: "Open Video…") }
    static var openVideosInPikapik: String { String(localized: "Open videos in pikapik") }
    static var openMusicInPikapik: String { String(localized: "Open music in pikapik") }
    static var openPicturesInPikapik: String { String(localized: "Open pictures in pikapik") }
    static var playerLicenses: String { String(localized: "Player Licenses") }
    static var sourceCode: String { String(localized: "Source Code") }
    static var removeAnApp: String { String(localized: "Remove an app") }
    static var removeApp: String { removeAnApp }
    static var offerCleanupOnTrash: String { String(localized: "Offer to clean up when an app goes to the Trash") }
    static var trashWatch: String { offerCleanupOnTrash }
    static var whatRunsInBackground: String { String(localized: "What runs in the background") }

    // Animations
    static var hideDockAutomatically: String { String(localized: "Hide the Dock automatically") }
    static var animationSpeed: String { String(localized: "Animation speed") }
    static var dockAppearDelay: String { String(localized: "Delay before the Dock appears") }
    static var dockDelay: String { dockAppearDelay }
    static var dockSlideSpeed: String { String(localized: "How fast the Dock slides out") }
    static var dockSpeed: String { dockSlideSpeed }
    static var minimizeEffect: String { String(localized: "Minimize effect") }
    static var bouncingIcons: String { String(localized: "Bouncing icons") }
    static var openingWindows: String { String(localized: "Opening windows") }
    static var saveDialogsAndResizing: String { String(localized: "Save dialogs and resizing") }
    static var quickLook: String { String(localized: "Quick Look") }
    static var columnsInFinder: String { String(localized: "Columns in Finder") }
    static var finderColumns: String { columnsInFinder }
    static var finderAnimations: String { String(localized: "Finder animations") }
    static var reduceMotionInAccessibility: String { String(localized: "Even calmer: Reduce Motion in Accessibility") }

    // Games
    static var gameMode: String { String(localized: "Game Mode") }
    static var yourGames: String { String(localized: "Your games") }
    static var showFPS: String { String(localized: "Show FPS") }
    static var cornerForFPS: String { String(localized: "Corner for FPS") }
    static var systemKeyboardShortcuts: String { String(localized: "System keyboard shortcuts") }
    static var gameSafeguards: String { String(localized: "Game safeguards") }
    static var moreGameSettings: String { String(localized: "More game settings") }
    static var gameCommandQ: String { String(localized: "The game doesn’t close") }
    static var gameCommandW: String { String(localized: "The game window doesn’t close") }
    static var gameAppSwitcher: String { String(localized: "Apps and windows don’t switch") }
    static var gameHide: String { String(localized: "The game doesn’t hide") }
    static var gameSpotlight: String { String(localized: "Search doesn’t pop up") }
    static var gameSiri: String { String(localized: "Siri and voice typing don’t start") }
    static var gameLaunchpad: String { String(localized: "The app grid doesn’t open") }
    static var gameMissionControl: String { String(localized: "The view of all windows doesn’t open") }
    static var gameAppWindows: String { String(localized: "The view of the game’s windows doesn’t open") }
    static var gameShowDesktop: String { String(localized: "The game doesn’t slide off the screen") }
    static var gameDesktops: String { String(localized: "Desktops don’t switch") }
    static var gameDesktopNumbers: String { String(localized: "Desktops don’t switch by number") }
    static var gameEmoji: String { String(localized: "Emoji don’t open") }
    static var gameLookUp: String { String(localized: "The dictionary doesn’t pop up") }
    static var gameFocusKeys: String { String(localized: "The keyboard stays in the game") }
    static var gameGlobe: String { String(localized: "🌐 shortcuts are paused") }
    static var gameControlClick: String { String(localized: "⌃-click works as a plain click") }
    static var gameShiftWheel: String { String(localized: "The wheel switches slots while you hold ⇧") }
    static var gameSwipes: String { String(localized: "Gestures don’t leave the game") }
    static var gameCursor: String { String(localized: "The pointer stays in the game") }
    static var gameDisplay: String { String(localized: "The screen stays on") }

    // Pet
    static var petOnDesktop: String { String(localized: "Pet on the desktop") }
    static var talksSometimes: String { String(localized: "Talks sometimes") }
    static var petTalks: String { talksSometimes }
    static var followsYourRhythm: String { String(localized: "Follows your rhythm") }
    static var petRhythm: String { followsYourRhythm }
    static var ball: String { String(localized: "Ball") }
    static var petBall: String { ball }
    static var wardrobe: String { String(localized: "Wardrobe") }
    static var petWardrobe: String { wardrobe }
    static var looks: String { String(localized: "Looks") }
    static var petLooks: String { looks }
    static var awards: String { String(localized: "Awards") }
    static var petAwards: String { awards }
    static var eraseProgress: String { String(localized: "Erase Progress…") }

    // Permissions
    static var administratorAccess: String { String(localized: "Administrator access") }
    static var adminAccess: String { administratorAccess }
    static var inputMonitoring: String { String(localized: "Input Monitoring") }
    static var screenRecording: String { String(localized: "Screen Recording") }
    static var systemAudioRecording: String { String(localized: "System Audio Recording") }
    static var iCloudDrive: String { String(localized: "iCloud Drive") }
    static var finderExtensions: String { String(localized: "Finder Extensions") }
    static var fullDiskAccess: String { String(localized: "Full Disk Access") }
    static var folders: String { String(localized: "Folders") }
    static var foldersPermission: String { folders }
    static var leftByDeletedApps: String { String(localized: "Left by deleted apps") }
    static var leftoverPermissions: String { leftByDeletedApps }
    static var otherAppsPermissions: String { String(localized: "Other apps’ permissions") }

    // About
    static var checkForUpdatesAutomatically: String { String(localized: "Check for updates automatically") }
    static var whatsNew: String { String(localized: "What’s New") }
    static var reportAProblem: String { String(localized: "Report a Problem") }
    static var licenseMIT: String { String(localized: "License (MIT)") }
    static var buyMeACoffee: String { String(localized: "Buy me a coffee") }
    static var sayThanks: String { String(localized: "Say thanks") }
}
