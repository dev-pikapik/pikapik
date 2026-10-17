import AppKit
import SwiftUI

enum Appearance: String, CaseIterable {
    case system, light, dark

    static var saved: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@Observable
final class Language {
    static let shared = Language()
    static let codes = ["en", "ru", "uk", "de", "fr", "es", "it", "pt-BR", "nl", "sv", "pl", "cs", "ro", "tr", "ja", "zh-Hans", "zh-Hant", "ko", "ar", "hi", "th", "vi", "id"]

    let atLaunch: String
    var selected: String {
        didSet {
            if selected.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([selected], forKey: "AppleLanguages")
            }
        }
    }

    private init() {
        atLaunch = Self.saved
        selected = atLaunch
    }

    private static var saved: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        return (domain?["AppleLanguages"] as? [String])?.first ?? ""
    }

    func load() {
        selected = Self.saved
    }

    static func name(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

struct GeneralSettings: View {
    @Bindable private var loginItem = LoginItem.shared
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage(Background.key) private var keepRunning = true
    @Bindable private var language = Language.shared
    @Bindable private var sync = SettingsSync.shared

    @ViewBuilder private var backupButtons: some View {
        Button("Import Settings…", systemImage: "square.and.arrow.down") { SettingsBackup.chooseImport() }
        Button("Export Settings…", systemImage: "square.and.arrow.up") { SettingsBackup.export() }
    }

    var body: some View {
        Form {
            SettingsHeader(tab: .general, text: String(localized: "How pikapik starts and looks"))
            Section {
                if loginItem.needsApproval { SettingsGuide.loginItems }
                Toggle(isOn: $loginItem.isOn) {
                    HStack {
                        RowLabel(Text("Open at Login"), Text(loginItem.needsApproval
                             ? String(localized: "Allow it in System Settings › General › Login Items")
                             : String(localized: "Starts on its own when you log in")))
                        if loginItem.needsApproval {
                            Spacer()
                            Button("Open", systemImage: "arrow.up.forward.app") { BackgroundTasks.openLoginItems() }
                        }
                    }
                }
                .settingAnchor(String(localized: "Open at Login"))
                #if !APPSTORE
                let stayTitle = String(localized: "Stay in the background after Quit")
                Toggle(isOn: $keepRunning) {
                    RowLabel(Text(stayTitle), Text("Shortcuts and Keep Awake keep working. Hold Option to quit completely"))
                }
                .settingAnchor(stayTitle)
                #endif
                LabeledContent("Appearance") {
                    AppearancePicker(selection: Binding(get: { appearance }, set: { appearance = $0; $0.apply() }))
                        .fixedSize()
                }
                .settingAnchor(String(localized: "Appearance"))
                Picker("Language", selection: $language.selected) {
                    Text("System").tag("")
                    Divider()
                    ForEach(Language.codes, id: \.self) { Text(verbatim: Language.name($0)).tag($0) }
                }
                .settingAnchor(String(localized: "Language"))
                if language.selected != language.atLaunch {
                    LabeledContent("Restart pikapik to apply") {
                        Button("Restart", systemImage: "arrow.clockwise") { SettingsWindow.restart() }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Section("Backup") {
                VStack(alignment: .leading, spacing: 10) {
                    RowLabel(Text("Settings file"), Text("Save all settings to a file, or load them from one"))
                    ViewThatFits(in: .horizontal) {
                        HStack { backupButtons }
                        VStack(alignment: .leading) { backupButtons }
                    }
                }
                .padding(.vertical, 2)
                .settingAnchor(String(localized: "Settings file"))
                if SettingsSync.isAvailable {
                    let syncTitle = String(localized: "Sync settings with iCloud")
                    Toggle(isOn: $sync.isEnabled) {
                        RowLabel(Text(syncTitle), Text(syncStatus))
                    }
                    .settingAnchor(syncTitle)
                }
                #if !APPSTORE
                if sync.state == .noDrive {
                    LabeledContent("Turn on iCloud Drive in System Settings") {
                        Button("Open", systemImage: "arrow.up.forward.app") { sync.openSettings() }
                    }
                    .foregroundStyle(.secondary)
                } else if sync.state == .noAccess {
                    LabeledContent("Needs a permission. Click to allow it.") {
                        Button("Allow") { Permissions.shared.ask([.iCloud]) }
                    }
                    .foregroundStyle(.secondary)
                }
                #endif
            }
            RestoreDefaultsSection(
                message: resetMessage,
                isDefault: appearance == .system && language.selected.isEmpty && !sync.isEnabled
            ) {
                sync.isEnabled = false
                appearance = .system
                Appearance.system.apply()
                language.selected = ""
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .onAppear { loginItem.refresh() }
        .alert(Text(verbatim: sync.alert?.title ?? ""), isPresented: Binding(get: { sync.alert != nil }, set: { if !$0 { sync.alert = nil } })) {
            Button("OK") {}
        } message: {
            Text(verbatim: sync.alert?.message ?? "")
        }
        .alert("Replace your settings?", isPresented: Binding(get: { sync.pendingImport != nil }, set: { if !$0 { sync.pendingImport = nil } }), presenting: sync.pendingImport) { item in
            Button("Replace") { sync.confirmImport(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("All pikapik settings will be replaced with the ones from “\(item.name)”.")
        }
    }

    private var resetMessage: String {
        #if APPSTORE
        SettingsSync.isAvailable
            ? String(localized: "Appearance and Language will follow the system again, and iCloud sync will turn off. Open at Login and the settings saved in iCloud stay as they are.")
            : String(localized: "Appearance and Language will follow the system again. Open at Login stays as it is.")
        #else
        String(localized: "Appearance and Language will follow the system again, and iCloud sync will turn off. Open at Login and the settings saved in iCloud Drive stay as they are.")
        #endif
    }

    private var syncStatus: String {
        switch sync.state {
        case .off: String(localized: "Same settings on all your Macs")
        case .synced(let date): String(localized: "Last synced at \(date.formatted(date: .omitted, time: .shortened))")
        case .noDrive: String(localized: "iCloud Drive is turned off on this Mac")
        case .noAccess: String(localized: "pikapik isn’t allowed to open iCloud Drive")
        case .failed(let message): String(localized: "Can’t sync: \(message)")
        }
    }
}

private struct AppearancePicker: View {
    @Binding var selection: Appearance

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Appearance.allCases, id: \.self) { item in
                ChoiceTile(title: item.title, selected: item == selection, action: { selection = item }) {
                    preview(item)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func preview(_ item: Appearance) -> some View {
        switch item {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            MiniWindow(dark: false)
                .overlay { MiniWindow(dark: true).mask(Diagonal()) }
        }
    }
}

private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let wallpaper = dark
            ? [Color(red: 0.16, green: 0.18, blue: 0.42), Color(red: 0.36, green: 0.20, blue: 0.48)]
            : [Color(red: 0.60, green: 0.78, blue: 0.97), Color(red: 0.88, green: 0.93, blue: 1.0)]
        let bar = Color(white: dark ? 0.36 : 0.82)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 1.5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 3, height: 3) }
                }
                .padding(.bottom, 2)
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(bar).frame(width: 12, height: 2) }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(width: 22)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(white: dark ? 0.22 : 0.93))
            VStack(alignment: .leading, spacing: 4) {
                ForEach([30, 22, 30, 16], id: \.self) { Capsule().fill(bar).frame(width: CGFloat($0), height: 2) }
                Spacer(minLength: 0)
            }
            .padding(.top, 9)
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: dark ? 0.13 : 1))
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3))
        .padding(.leading, 9)
        .padding(.top, 8)
        .background(LinearGradient(colors: wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, dark ? .dark : .light)
        .accessibilityHidden(true)
    }
}

private struct Diagonal: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
