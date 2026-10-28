import AppKit
import SwiftUI

enum SettingsWindow {
    private static let bashExecutableURL = URL(fileURLWithPath: SystemPath.bash)
    private static let tccutilPath = SystemPath.tccutil

    @Observable
    final class Model {
        var selection: SettingsTab? = .general {
            didSet {
                guard !navigating, let oldValue, oldValue != selection else { return }
                back.append(oldValue)
                forward = []
            }
        }
        var search = ""
        var highlight: String?
        var systemShortcuts: [SystemGameShortcut] = []
        var confirmingReset = false
        private(set) var back: [SettingsTab] = []
        private(set) var forward: [SettingsTab] = []
        @ObservationIgnored private var navigating = false

        var searchItems: [SettingsItem] { SettingsItem.all + systemShortcuts.map(SettingsItem.shortcut) }
        var highlightedShortcut: SystemGameShortcut? { systemShortcuts.first { $0.anchor == highlight } }

        func refreshShortcuts() { systemShortcuts = SystemShortcutCatalog.load().filter(\.listed) }

        func goBack() {
            guard let tab = back.popLast() else { return }
            selection.map { forward.append($0) }
            move(to: tab)
        }

        func goForward() {
            guard let tab = forward.popLast() else { return }
            selection.map { back.append($0) }
            move(to: tab)
        }

        private func move(to tab: SettingsTab) {
            navigating = true
            selection = tab
            navigating = false
        }

        func open(_ item: SettingsItem) {
            selection = item.tab
            highlight = nil
            highlight = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if self.highlight == item.id { self.highlight = nil }
            }
        }
    }

    static let model = Model()
    private(set) static var window: NSWindow?

    static var preview: some View { SettingsRoot() }

    static let minSize = NSSize(width: 660, height: 460)

    static func show(_ tab: SettingsTab? = nil) {
        if let tab {
            model.search = ""
            model.selection = tab
        }
        if window == nil { create() }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard !NSApp.isActive, window?.isVisible == true else { return }
            NSApp.bringForward()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private static func create() {
        let width: CGFloat = 860
        let height = min(800, (NSScreen.main?.visibleFrame.height ?? 900) - 40)
        let host = NSHostingController(rootView: SettingsRoot())
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.fullScreenNone)
        window.isReleasedWhenClosed = false
        window.contentMinSize = minSize
        window.title = (model.selection ?? .general).title
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.setFrameAutosaveName("Settings Frame")
        let saved = window.contentRect(forFrameRect: window.frame).size
        window.setContentSize(NSSize(width: max(saved.width, minSize.width), height: max(saved.height, minSize.height)))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NewMarks.shared.leave((model.selection ?? .general).rawValue)
            MainActor.assumeIsolated { GuideText.forget() }
            NSApp.setActivationPolicy(.accessory)
        }
        self.window = window
        NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { event in
            guard event.window === window, event.buttonNumber == 3 || event.buttonNumber == 4, !HideAppTool.isRecording else { return event }
            if event.type == .otherMouseDown { event.buttonNumber == 3 ? model.goBack() : model.goForward() }
            return nil
        }
    }

    static func restart(opening argument: String = "--settings", resetting service: String? = nil) {
        #if APPSTORE
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [argument]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { if error == nil { Background.quit() } }
        }
        #else
        let helper = Process()
        helper.executableURL = bashExecutableURL
        helper.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; [ -z \"$4\" ] || \(tccutilPath) reset \"$4\" \"$3\"; open \"$2\" --args \"$5\"",
                            "pika-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
                            Bundle.main.bundleIdentifier ?? "", service ?? "", argument]
        try? helper.run()
        Background.quit()
        #endif
    }
}

private struct SettingsRoot: View {
    private let copy = MainCopy.shared

    var body: some View {
        if copy.role == .passive { PassiveCopyView() } else { SettingsView() }
    }
}

private struct SettingsView: View {
    @Bindable private var model = SettingsWindow.model
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        let tab = model.selection ?? .general
        NavigationSplitView(columnVisibility: $columns) {
            ScrollViewReader { proxy in
                List(selection: $model.selection) {
                    if model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section { rows([.general]) }
                        #if APPSTORE
                        Section("Mac") { rows([.battery, .keepAwake, .brightness, .fans, .temperatures, .ports]) }
                        #else
                        Section("Mac") { rows([.battery, .keepAwake, .brightness, .displays, .fans, .temperatures, .speedTest, .ports]) }
                        #endif
                        Section("Enhancements") { rows([.sound, .keyboard, .mouse, .windows, .dock, .finder, .animations]) }
                        Section("Apps") { rows([.player, .uninstaller, .background, .games, .pet]) }
                        Section("Info") { rows([.permissions, .about]) }
                    } else {
                        results
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: model.selection, initial: true) { scroll(proxy) }
                .onChange(of: model.search.isEmpty) { scroll(proxy) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            detail(tab)
                .navigationSplitViewColumnWidth(min: 440, ideal: 520)
                .navigationTitle(tab.title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                        } label: { Label("Sidebar", symbol: .sidebarLeading) }
                        .help(Text("Sidebar"))
                    }
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button { model.goBack() } label: { Label("Back", symbol: .chevronBackward) }
                                .keyboardShortcut("[")
                                .disabled(model.back.isEmpty)
                            Button { model.goForward() } label: { Label("Forward", symbol: .chevronForward) }
                                .keyboardShortcut("]")
                                .disabled(model.forward.isEmpty)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .searchable(text: $model.search, placement: .sidebar)
        .frame(minWidth: SettingsWindow.minSize.width, minHeight: SettingsWindow.minSize.height)
        .onChange(of: tab, initial: true) { old, tab in
            if old != tab { NewMarks.shared.leave(old.rawValue) }
            NewMarks.shared.open(tab.rawValue)
            SettingsWindow.window?.title = tab.title
            PetProgress.shared.mark("page:\(tab.rawValue)")
            if tab == .pet { PetProgress.shared.add(.visits) }
        }
        .onAppear { model.refreshShortcuts() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshShortcuts() }
        #if !APPSTORE
        .environment(\.openURL, OpenURLAction { url in
            if url.host == "github.com", url.pathComponents.dropFirst().first == "dev-pikapik" { PetProgress.shared.add(.github) }
            return .systemAction(url)
        })
        #endif
    }

    private func rows(_ tabs: [SettingsTab]) -> some View {
        ForEach(tabs.filter(\.isAvailable)) { tab in
            Label {
                HStack(spacing: 6) {
                    Text(tab.title)
                    if NewMarks.shared.isNew(tab: tab.rawValue) { NewDot() }
                }
            } icon: { tab.icon() }
                .tag(tab)
                .badge(tab == .pet ? PetProgress.shared.freshAwards : 0)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let tab = model.selection else { return }
        DispatchQueue.main.async { proxy.scrollTo(tab) }
    }

    @ViewBuilder
    private var results: some View {
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = model.searchItems.filter { $0.matches(query) }.sorted {
            let left = SettingsSearch.score(query, title: $0.title, keys: $0.keys)
            let right = SettingsSearch.score(query, title: $1.title, keys: $1.keys)
            return left == right ? $0.id.localizedStandardCompare($1.id) == .orderedAscending : left > right
        }
        let tabs = SettingsTab.allCases.filter { tab in
            tab.isAvailable && (tab.title.localizedStandardContains(query) || items.contains { $0.tab == tab })
        }
        if tabs.isEmpty {
            Text("No Results")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        ForEach(tabs) { tab in
            Label { Text(tab.title) } icon: { tab.icon() }
                .tag(tab)
            ForEach(items.filter { $0.tab == tab }) { item in
                Button { model.open(item) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).foregroundStyle(.secondary).lineLimit(2)
                        if let detail = item.detail {
                            Text(verbatim: detail).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                        }
                    }
                        .padding(.leading, SettingsTab.iconSize + 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func detail(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .keepAwake: KeepAwakeSettings()
        case .brightness: BrightnessSettings()
        case .fans:
            #if APPSTORE
            EmptyView()
            #else
            FanSettings()
            #endif
        case .battery: BatterySettings()
        case .temperatures: TemperatureSettings()
        #if !APPSTORE
        case .displays: DisplayScaleSettings()
        case .speedTest: SpeedTestSettings()
        #endif
        case .ports: PortsPage()
        case .sound: ToolsSettings(tab: .sound, text: String(localized: "Each app gets its own volume"))
        case .keyboard: ToolsSettings(tab: .keyboard, text: String(localized: "Switch language, fix wrong layout, Home and End"))
        case .mouse: ToolsSettings(tab: .mouse, text: String(localized: "Scrolling, side buttons and pointer speed"))
        case .windows:
            ToolsSettings(
                tab: .windows,
                text: String(localized: "Fixes for windows and quitting apps"),
                headings: ["window-zoom": "Size", "quit-on-close": "Closing and Quitting"]
            )
        case .dock: ToolsSettings(tab: .dock, text: String(localized: "Hide apps with a click and keep the Dock on one display"))
        case .finder: ToolsSettings(tab: .finder, text: String(localized: "Create, convert and compress files right in Finder"))
        case .animations:
            #if APPSTORE
            AnimationLinksPage()
            #else
            AnimationsPage()
            #endif
        case .player:
            #if APPSTORE
            EmptyView()
            #else
            PlayerPage()
            #endif
        case .uninstaller:
            #if APPSTORE
            EmptyView()
            #else
            UninstallerPage()
            #endif
        case .background: BackgroundPage()
        case .games: GameModePage()
        case .pet: PetPage()
        case .permissions: PermissionsView()
        case .about: AboutView()
        }
    }
}

extension View {
    func settingAnchor(_ id: String) -> some View {
        modifier(SettingAnchor(id: id))
    }

    func settingsPage() -> some View {
        modifier(SettingsPage())
    }

    func whileShown(in window: @escaping (NSWindow) -> Bool = { $0 === SettingsWindow.window }, _ shown: @escaping (Bool) -> Void) -> some View {
        modifier(WhileShown(window: window, shown: shown))
    }
}

private struct WhileShown: ViewModifier {
    let window: (NSWindow) -> Bool
    let shown: (Bool) -> Void
    @State private var on = false

    private func set(_ value: Bool) {
        guard value != on else { return }
        on = value
        shown(value)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { set(true) }
            .onDisappear { set(false) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
                guard let changed = note.object as? NSWindow, window(changed) else { return }
                set(changed.occlusionState.contains(.visible))
            }
    }
}

private struct SettingAnchor: ViewModifier {
    let id: String
    private let model = SettingsWindow.model

    func body(content: Content) -> some View {
        content
            .id(id)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(model.highlight == id ? 0.25 : 0))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -6)
                    .animation(.easeInOut(duration: 0.4), value: model.highlight)
            }
    }
}

private struct SettingsPage: ViewModifier {
    private let model = SettingsWindow.model

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .labeledContentStyle(CenteredLabeledContentStyle())
                .toggleStyle(CenteredSwitchStyle())
                .labelStyle(.titleAndIcon)
                .modifier(AppDropPage())
                .onAppear { scroll(proxy) }
                .onChange(of: model.highlight) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = model.highlight else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

struct RestoreDefaultsSection: View {
    let message: String
    let isDefault: Bool
    let reset: () -> Void
    @Bindable private var model = SettingsWindow.model

    var body: some View {
        Section {
        } footer: {
            HStack {
                Spacer()
                Button("Restore Defaults…", symbol: .arrowCounterclockwise) { model.confirmingReset = true }
                    .disabled(isDefault)
            }
        }
        .alert("Restore default settings?", isPresented: $model.confirmingReset) {
            Button("Restore Defaults", action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct SettingsHeader: View {
    let tab: SettingsTab
    var title: String?
    let text: String
    var appIcon: NSImage?

    var body: some View {
        Section {
            VStack(spacing: 0) {
                Group {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .padding(-6)
                            .accessibilityHidden(true)
                    } else {
                        tab.icon(size: 48)
                    }
                }
                .padding(.bottom, 12)
                Text(title ?? tab.title)
                    .font(.title.bold())
                    .padding(.bottom, 4)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .padding(.horizontal, 24)
        }
    }
}

private struct ToolsSettings: View {
    let tab: SettingsTab
    let text: String
    var headings: [String: LocalizedStringKey] = [:]

    private var tools: [any Tool] { ToolRegistry.shared.tools.filter { $0.tab == tab } }

    var body: some View {
        Form {
            SettingsHeader(tab: tab, text: text)
            #if APPSTORE
            if tab == .mouse {
                Section {
                    SystemSettingsRow(
                        title: String(localized: "Turn off pointer acceleration"),
                        subtitle: Text("The pointer moves as far as your hand, at any speed. Mouse only."),
                        url: URL(string: SystemPane.mouse)!,
                        guide: SettingsGuide(pane: .mouse, steps: [.button("Advanced…"), .toggle("Pointer acceleration", on: false)])
                    )
                }
            }
            #endif
            ForEach(tools, id: \.id) { tool in
                if headings[tool.id] != nil || NewMarks.shared.isNew(row: tool.id) {
                    Section { tool.settingsView.needs(tool.needs) } header: { NewTitle(title: headings[tool.id], row: tool.id) }
                } else {
                    Section { tool.settingsView.needs(tool.needs) }
                }
            }
            #if APPSTORE
            if tab == .finder { Section { HiddenFilesHint() } }
            #endif
            RestoreDefaultsSection(
                message: String(localized: "These will turn off and go back to their default options: \(tools.filter { !$0.isDefault }.map(\.title).formatted(.list(type: .and)))"),
                isDefault: tools.allSatisfy(\.isDefault)
            ) {
                tools.forEach { $0.reset() }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                PermissionBar(permissions: tools.flatMap(\.needs))
                if tab == .finder { FinderRestartBar() }
            }
        }
        .environment(\.inSettings, true)
    }
}

struct SystemSettingsRow: View {
    let title: String
    var subtitle: Text?
    let url: URL
    var guide: SettingsGuide?

    var body: some View {
        if let guide { guide }
        LabeledContent {
            Button("Open", symbol: .arrowUpForwardApp) { NSWorkspace.shared.open(url) }
        } label: {
            RowLabel(Text(title), subtitle)
        }
        .settingAnchor(title)
    }
}

#if APPSTORE
private struct AnimationLinksPage: View {
    private static let desktop = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!

    var body: some View {
        Form {
            SettingsHeader(tab: .animations, text: String(localized: "Each button takes you to an animation setting in System Settings"))
            Section {
                SystemSettingsRow(
                    title: String(localized: "Minimize effect"),
                    subtitle: Text("Choose “Scale Effect” for a quicker animation"),
                    url: Self.desktop,
                    guide: SettingsGuide(pane: .desktop, steps: [.popup(nil, from: "Genie Effect", to: "Scale Effect")])
                )
            }
            Section {
                SystemSettingsRow(
                    title: String(localized: "Bouncing icons"),
                    subtitle: Text("Turn off “Animate opening applications”"),
                    url: Self.desktop,
                    guide: SettingsGuide(pane: .desktop, steps: [.toggle("Animate opening applications", on: false)])
                )
            }
            Section {
                SystemSettingsRow(
                    title: String(localized: "Hide the Dock automatically"),
                    subtitle: Text("Turn on “Automatically hide and show the Dock”"),
                    url: Self.desktop,
                    guide: SettingsGuide(pane: .desktop, steps: [.toggle("Automatically hide and show the Dock", on: true)])
                )
            }
            Section {
                SystemSettingsRow(title: String(localized: "Even calmer: Reduce Motion in Accessibility"), url: SettingsGuide.reduceMotionLink, guide: .reduceMotion)
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
#endif

extension NSApplication {
    func bringForward() {
        activate(ignoringOtherApps: true)
    }
}
