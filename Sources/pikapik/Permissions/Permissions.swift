import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

enum Permission: CaseIterable {
    case accessibility, inputMonitoring, screenRecording, systemAudio
    #if !APPSTORE
    case fans
    #endif
    case finder
    #if APPSTORE
    case folders
    #else
    case iCloud, fullDisk
    #endif

    private var info: (icon: String, symbol: Symbol, title: String, subtitle: String) {
        switch self {
        case .accessibility:
            #if APPSTORE
            ("com.apple.graphic-icon.accessibility", .accessibility,
             Self.accessibilityTitle, String(localized: "Lets the app change clicks and keys"))
            #else
            ("com.apple.graphic-icon.accessibility", .accessibility,
             Self.accessibilityTitle, String(localized: "Lets the app change clicks and keys and manage windows"))
            #endif
        case .inputMonitoring:
            ("com.apple.graphic-icon.input-monitoring", .keyboardBadgeEye,
             SettingTitle.inputMonitoring, String(localized: "Lets the app see clicks and keys"))
        case .screenRecording:
            ("com.apple.graphic-icon.screen-recording", .rectangleDashedBadgeRecord,
             SettingTitle.screenRecording,
             FrameRateMeter.hasTrace ? String(localized: "Needed for some games") : String(localized: "Needed to count frames"))
        case .systemAudio:
            ("", .waveform, SettingTitle.systemAudioRecording, String(localized: "To change each app’s volume"))
        #if !APPSTORE
        case .fans:
            ("", .lockShield, SettingTitle.adminAccess, String(localized: "Lets the app change the fan speed and turn off services for the whole Mac"))
        #endif
        case .finder:
            ("", .puzzlepieceExtension,
             SettingTitle.finderExtensions, String(localized: "Lets the app add items to the right-click menu in Finder"))
        #if APPSTORE
        case .folders:
            ("", .folderFill, SettingTitle.foldersPermission, String(localized: "Lets the app save new files next to yours and see your background tasks"))
        #else
        case .iCloud:
            ("", .icloudFill,
             SettingTitle.iCloudDrive, String(localized: "Lets the app keep your settings in iCloud Drive to sync them"))
        case .fullDisk:
            ("com.apple.graphic-icon.privacy", .handRaisedFill,
             SettingTitle.fullDiskAccess, String(localized: "Lets the app find permissions left by deleted apps"))
        #endif
        }
    }

    private static var hasDeviceControl: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }

    static var accessibilityTitle: String {
        hasDeviceControl ? String(localized: "Device Control and Data Access") : String(localized: "Accessibility")
    }

    var guidePage: String? {
        switch self {
        case .accessibility: Self.hasDeviceControl ? "Device Control and Data Access" : "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording, .systemAudio: "Screen & System Audio Recording"
        default: nil
        }
    }

    var icon: String { info.icon }
    var symbol: Symbol { info.symbol }
    var title: String { info.title }
    var subtitle: String { info.subtitle }

    var barText: String {
        self == .systemAudio ? String(localized: "To change each app’s volume, allow “\(title)”") : "\(title): \(subtitle)"
    }

    private var pane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .systemAudio: "Privacy_AudioCapture"
        default: "Privacy_AllFiles"
        }
    }

    var isShown: Bool {
        switch self {
        case .screenRecording:
            GameModeTool.shared.showsFrameRate && !Permissions.shared.screenRecording && (!FrameRateMeter.hasTrace || GameModeTool.shared.needsRecording)
        case .systemAudio:
            if #available(macOS 14.2, *) { AppVolumeTool.shared.isEnabled || Permissions.shared.systemAudioRequested } else { false }
        #if !APPSTORE
        case .iCloud: SettingsSync.shared.isEnabled
        #endif
        case .finder: FinderExtension.all.contains { $0.isActive || $0.needsSettings }
        default: true
        }
    }

    var isGranted: Bool {
        let permissions = Permissions.shared
        return switch self {
        case .accessibility: permissions.accessibility
        case .inputMonitoring: permissions.inputMonitoring
        case .screenRecording: permissions.screenRecording
        case .systemAudio: permissions.systemAudio
        #if !APPSTORE
        case .fans: FanControl.shared.ready
        case .iCloud: SettingsSync.shared.state != .noAccess
        case .fullDisk: permissions.fileAccess
        #endif
        case .finder: !FinderExtension.all.contains(where: \.needsSettings)
        #if APPSTORE
        case .folders: permissions.fileAccess
        #endif
        }
    }

    var isBusy: Bool {
        #if APPSTORE
        false
        #else
        self == .fans && FanControl.shared.busy
        #endif
    }

    var error: String? {
        #if APPSTORE
        nil
        #else
        self == .fans ? FanControl.shared.error : nil
        #endif
    }

    var opensSettingsToAllow: Bool {
        #if APPSTORE
        self == .systemAudio ? Permissions.shared.systemAudioAsked : self != .folders
        #else
        self == .systemAudio ? Permissions.shared.systemAudioAsked : self != .fans
        #endif
    }

    var opensSettingsToTurnOff: Bool {
        #if APPSTORE
        self == .accessibility || self == .inputMonitoring || self == .screenRecording || self == .systemAudio || self == .finder
        #else
        false
        #endif
    }

    var restartsToTurnOff: Bool {
        #if APPSTORE
        false
        #else
        self == .accessibility || self == .inputMonitoring || self == .screenRecording || self == .systemAudio
        #endif
    }

    func allow() {
        let permissions = Permissions.shared
        switch self {
        case .accessibility, .inputMonitoring, .screenRecording:
            permissions.request([self])
            permissions.openSettings(pane)
        case .systemAudio:
            if #available(macOS 14.2, *) {
                let asked = permissions.systemAudioAsked
                permissions.systemAudioAsked = true
                AudioCaptureProbe.shared.allow(opening: asked ? { permissions.openSettings(pane) } : nil)
            }
        #if !APPSTORE
        case .fans: FanControl.shared.install()
        case .iCloud: SettingsSync.shared.openSettings()
        case .fullDisk: permissions.openSettings(pane)
        #endif
        case .finder: FinderExtension.allow()
        #if APPSTORE
        case .folders:
            FolderAccess.allow()
            permissions.refresh()
        #endif
        }
    }

    func turnOff() {
        let permissions = Permissions.shared
        switch self {
        case .accessibility, .inputMonitoring, .screenRecording:
            #if APPSTORE
            permissions.openSettings(pane)
            #else
            SettingsWindow.restart(opening: "--permissions", resetting: self == .accessibility ? "Accessibility" : self == .inputMonitoring ? "ListenEvent" : "ScreenCapture")
            #endif
        case .systemAudio:
            #if APPSTORE
            permissions.openSettings(pane)
            #else
            permissions.systemAudioAsked = false
            permissions.setSystemAudio(false)
            SettingsWindow.restart(opening: "--permissions", resetting: "AudioCapture")
            #endif
        #if !APPSTORE
        case .fans: FanControl.shared.uninstall()
        case .iCloud:
            SettingsSync.shared.isEnabled = false
            ["Ubiquity", "FileProviderDomain"].forEach(permissions.reset)
        case .fullDisk:
            permissions.reset("SystemPolicyAllFiles")
            permissions.refresh()
            if permissions.fileAccess { permissions.openSettings(pane) }
        #endif
        case .finder: FinderExtension.turnOff()
        #if APPSTORE
        case .folders:
            FolderAccess.forget()
            permissions.refresh()
        #endif
        }
    }
}

@Observable
final class Permissions {
    static let shared = Permissions()
    private static let tccutilExecutableURL = URL(fileURLWithPath: SystemPath.tccutil)

    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var inputMonitoring = CGPreflightListenEventAccess()
    private(set) var fileAccess = Permissions.hasFileAccess
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    private(set) var systemAudio = UserDefaults.standard.bool(forKey: PreferenceKey.systemAudioGranted) {
        didSet { UserDefaults.standard.set(systemAudio, forKey: PreferenceKey.systemAudioGranted) }
    }
    private(set) var systemAudioRequested = false
    var systemAudioAsked = UserDefaults.standard.bool(forKey: PreferenceKey.systemAudioAsked) {
        didSet { UserDefaults.standard.set(systemAudioAsked, forKey: PreferenceKey.systemAudioAsked) }
    }

    var allGranted: Bool { accessibility && inputMonitoring }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    private static var hasFileAccess: Bool {
        #if APPSTORE
        FolderAccess.isGranted
        #else
        let descriptor = open(LeftoverPermissions.systemDatabase, O_RDONLY)
        defer { if descriptor >= 0 { close(descriptor) } }
        return descriptor >= 0
        #endif
    }

    func request(_ wanted: [Permission]) {
        let ax = !accessibility && wanted.contains(.accessibility)
        let input = !inputMonitoring && wanted.contains(.inputMonitoring)
        #if !APPSTORE
        if ax { reset("Accessibility") }
        if input { reset("ListenEvent") }
        #endif
        if ax {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if input {
            CGRequestListenEventAccess()
        }
        if !screenRecording && wanted.contains(.screenRecording) {
            CGRequestScreenCaptureAccess()
        }
        if wanted.contains(.systemAudio) { systemAudioRequested = true }
        startPolling()
    }

    func ask(_ missing: [Permission]) {
        request(missing)
        SettingsWindow.show(.permissions)
        if let first = missing.first {
            SettingsWindow.model.open(SettingsItem(tab: .permissions, title: first.title))
        }
    }

    #if !APPSTORE
    func reset(_ service: String) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = Self.tccutilExecutableURL
        process.arguments = ["reset", service, id]
        try? process.run()
        process.waitUntilExit()
    }
    #endif

    func refresh() {
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let files = Self.hasFileAccess
        let capture = CGPreflightScreenCaptureAccess()
        guard ax != accessibility || input != inputMonitoring || files != fileAccess || capture != screenRecording else { return }
        accessibility = ax
        inputMonitoring = input
        fileAccess = files
        screenRecording = capture
        onChange?()
    }

    func setSystemAudio(_ granted: Bool) {
        guard granted != systemAudio else { return }
        systemAudio = granted
        onChange?()
    }

    func checkSystemAudio() {
        if #available(macOS 14.2, *) { AudioCaptureProbe.shared.check() }
    }

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            refresh()
            if allGranted {
                timer.invalidate()
                self.timer = nil
            }
        }
    }

    func openSettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    #if APPSTORE
    static var privacyLists: [(title: String, icon: String, symbol: Symbol, pane: String)] {
        [
            (Permission.accessibilityTitle, "com.apple.graphic-icon.accessibility", .accessibility, "Privacy_Accessibility"),
            (String(localized: "Screen Recording"), "com.apple.graphic-icon.screen-recording", .rectangleDashedBadgeRecord, "Privacy_ScreenCapture"),
            (String(localized: "Input Monitoring"), "com.apple.graphic-icon.input-monitoring", .keyboardBadgeEye, "Privacy_ListenEvent"),
            (String(localized: "Full Disk Access"), "com.apple.graphic-icon.privacy", .handRaisedFill, "Privacy_AllFiles"),
            (String(localized: "Automation"), "com.apple.graphic-icon.automation", .gearshape2, "Privacy_Automation"),
            (String(localized: "App Management"), "", .appBadgeCheckmark, "Privacy_AppBundles"),
            (String(localized: "Files and Folders"), "", .folderFill, "Privacy_FilesAndFolders"),
            (String(localized: "Camera"), "com.apple.graphic-icon.video-camera", .camera, "Privacy_Camera"),
            (String(localized: "Microphone"), "com.apple.graphic-icon.microphone", .mic, "Privacy_Microphone"),
            (String(localized: "Developer Tools"), "com.apple.graphic-icon.developer-tools", .hammer, "Privacy_DevTools"),
            (String(localized: "Bluetooth"), "com.apple.graphic-icon.bluetooth", .dotRadiowavesLeftAndRight, "Privacy_Bluetooth"),
        ]
    }
    #endif
}
