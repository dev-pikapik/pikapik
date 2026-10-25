import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct NeedsPermission: ViewModifier {
    let permissions: [Permission]

    func body(content: Content) -> some View {
        let missing = permissions.filter { !$0.isGranted }
        content
            .disabled(!missing.isEmpty)
            .opacity(missing.isEmpty ? 1 : 0.5)
            .overlay {
                if !missing.isEmpty {
                    Button { Permissions.shared.ask(missing) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Needs a permission. Click to allow it."))
                    .accessibilityLabel(Text("Needs a permission. Click to allow it."))
                }
            }
    }
}

extension View {
    func needs(_ permissions: [Permission]) -> some View {
        modifier(NeedsPermission(permissions: permissions))
    }
}

struct PermissionBar: View {
    let permissions: [Permission]
    var text: LocalizedStringKey?

    var body: some View {
        let missing = Permission.allCases.filter { permissions.contains($0) && !$0.isGranted }
        if !missing.isEmpty {
            HStack(spacing: 12) {
                Image(.lock)
                    .accessibilityHidden(true)
                if let text {
                    Text(text)
                } else {
                    Text(verbatim: missing.map(\.barText).joined(separator: "\n"))
                }
                Spacer(minLength: 0)
                Button("Allow") { Permissions.shared.ask(missing) }
            }
            .noticeBar()
        }
    }
}

struct PermissionsView: View {
    private let permissions = Permissions.shared
    private let sync = SettingsSync.shared
    #if APPSTORE
    @State private var asks = PrivacyAsksModel()
    #endif

    var body: some View {
        let others = Permission.allCases.filter { $0.isShown && $0 != .accessibility && $0 != .inputMonitoring }
        let othersGranted = others.allSatisfy(\.isGranted)
        let allSet = othersGranted
            ? String(localized: "Both permissions are on and every tool is working")
            : String(localized: "Some tools also need a permission from the list below")
        let done = othersGranted ? String(localized: "All set") : String(localized: "Both permissions are on")
        Form {
            SettingsHeader(
                tab: .permissions,
                title: permissions.allGranted ? done : String(localized: "Permissions for some tools"),
                text: permissions.allGranted
                    ? allSet
                    : String(localized: "Only some tools need these permissions, and the rest work without them")
            )
            Section {
                if let page = Permission.allCases.first(where: { $0.guidePage != nil && $0.isShown && !$0.isGranted })?.guidePage {
                    SettingsGuide(pane: .privacy, steps: [.page(page), .app(on: true)])
                }
                PermissionRow(permission: .accessibility)
                PermissionRow(permission: .inputMonitoring)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !permissions.allGranted {
                        Text("pikapik checks every 1.5 seconds, so there’s no need to restart anything. If it’s already in a list but doesn’t work, remove it with the − button and add it again.")
                    }
                    #if APPSTORE
                    if permissions.accessibility || permissions.inputMonitoring {
                        Text("macOS lets you turn these off only in System Settings. The button opens the right list, where you switch pikapik off.")
                    }
                    #endif
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("For some features") {
                ForEach(others, id: \.self) { permission in
                    if permission == .finder, !permission.isGranted { SettingsGuide.finderExtensions }
                    PermissionRow(permission: permission)
                    if let error = permission.error {
                        Label(error, symbol: .exclamationmarkTriangleFill)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            #if APPSTORE
            Section {
                ForEach(Permissions.privacyLists, id: \.pane) { list in
                    PrivacyListRow(title: list.title, icon: list.icon, symbol: list.symbol, pane: list.pane, apps: asks.apps)
                        .settingAnchor(list.pane)
                }
            } header: {
                NewTitle(title: "Other apps’ permissions", row: "apps-can-ask")
            } footer: {
                Text("Deleted apps keep their permissions: select one in the list and press − or turn it off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingAnchor(SettingTitle.leftoverPermissions)
            .onAppear { asks.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in asks.refresh() }
            #else
            LeftoverPermissionsSection()
            #endif
        }
        .formStyle(.grouped)
        .settingsPage()
        .animation(.snappy, value: permissions.allGranted)
        .animation(.snappy, value: others)
        .onAppear {
            FinderExtension.all.forEach { $0.refresh() }
            #if !APPSTORE
            FanControl.shared.probe()
            #endif
            if sync.state == .noAccess { sync.refresh() }
        }
        .whileShown { permissions.watch($0) }
    }
}

struct PermissionRow: View {
    let permission: Permission
    @State private var confirming = false

    private var pages: [String]? {
        guard permission == .accessibility || permission == .inputMonitoring else { return nil }
        let tools = ToolRegistry.shared.tools.filter { $0.isEnabled && $0.needs.contains(permission) }
        return SettingsTab.allCases.filter { tab in tools.contains { $0.tab == tab } }.map(\.title)
    }

    private var usage: String? {
        guard let pages else { return nil }
        let list = pages.formatted(.list(type: .and))
        if pages.isEmpty { return String(localized: "No tool you turned on needs it") }
        return permission.isGranted
            ? String(localized: "Used by tools you turned on: \(list)")
            : String(localized: "Needed by tools you turned on: \(list)")
    }

    @ViewBuilder
    private var label: some View {
        let content = HStack(spacing: 10) {
            PermissionIcon(type: permission.icon, symbol: permission.symbol)
            RowLabel(Text(permission.title), Text(verbatim: usage.map { permission.subtitle + "\n" + $0 } ?? permission.subtitle))
        }
        if permission == .systemAudio {
            content.help(Text("pikapik passes each app’s sound through itself to change its volume. Nothing is recorded or saved."))
        } else {
            content
        }
    }

    var body: some View {
        let granted = permission.isGranted
        LabeledContent {
            HStack(spacing: 8) {
                if permission.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else if granted {
                    PermissionButton(title: "Turn Off", opensSettings: permission.opensSettingsToTurnOff) {
                        if permission.restartsToTurnOff { confirming = true } else { permission.turnOff() }
                    }
                } else {
                    PermissionButton(title: "Allow", opensSettings: permission.opensSettingsToAllow, action: permission.allow)
                }
                Image(granted ? .checkmarkCircleFill : .xmarkCircleFill)
                    .font(.title3)
                    .foregroundStyle(granted ? .green : pages?.isEmpty == true ? .secondary : .orange)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(granted ? String(localized: "Allowed") : String(localized: "Not allowed"))
            }
        } label: {
            label
        }
        .settingAnchor(permission.title)
        .confirmationDialog("Turn off \(permission.title)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { permission.turnOff() }
        } message: {
            Text("pikapik will restart, and the tools that need it will turn grey until you allow it again.")
        }
    }
}

private struct PermissionButton: View {
    let title: LocalizedStringKey
    let opensSettings: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if opensSettings {
                Label(title, symbol: .arrowUpForwardApp)
            } else {
                Text(title)
            }
        }
    }
}

struct PermissionIcon: View {
    let type: String
    let symbol: Symbol

    var body: some View {
        let size = SettingsTab.iconSize + 4
        if let type = UTType(type) {
            let _ = IconStyle.shared.theme
            Image(nsImage: NSWorkspace.shared.icon(for: type))
                .resizable()
                .frame(width: size, height: size)
                .padding(-2)
                .accessibilityHidden(true)
        } else {
            SectionIcon(symbol: symbol, color: .blue, size: SettingsTab.iconSize)
        }
    }
}
