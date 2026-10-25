import SwiftUI

struct MenuView: View {
    static let defaultHidden = [
        ToolID.appVolume, ToolID.archive, ToolID.brightness, ToolID.commandKeys, ToolID.compress, ToolID.convert,
        ToolID.desktopIcons, ToolID.dockDisplay, ToolID.dockHide, ToolID.fans, ToolID.finderCut, ToolID.finderDelete,
        ToolID.finderOpen, ToolID.gameMode, ToolID.hiddenFiles, ToolID.hideApp, ToolID.homeEnd, ToolID.keyRepeat,
        ToolID.layoutFix, ToolID.middleClick, ToolID.newFile, ToolID.quitOnClose, ToolID.sideButtons, ToolID.speedTest,
        ToolID.temperatures, ToolID.wheelDirection, ToolID.wheelLines, ToolID.windowZoom,
    ].joined(separator: ",")

    let registry: ToolRegistry
    private let permissions = Permissions.shared
    @Bindable private var keepAwake = KeepAwake.shared
    @AppStorage(PreferenceKey.quickHidden) private var hiddenList = MenuView.defaultHidden
    @State private var customizing = false
    @State private var keepAwakeOpen = false
    @State private var contentHeight: CGFloat = 0

    private var showsSpeedTest: Bool {
        #if APPSTORE
        false
        #else
        isShown(ToolID.speedTest)
        #endif
    }

    // Room left for the rows: the screen the panel is on, minus footer, padding and menu bar gap.
    private var maxRowsHeight: CGFloat {
        ((NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 700) - 140
    }

    private var hidden: Set<String> { Set(hiddenList.split(separator: ",").map(String.init)) }

    private func isShown(_ id: String) -> Bool {
        return customizing || !hidden.contains(id) || id == GameModeTool.shared.id && GameModeTool.shared.isPlaying
    }

    #if APPSTORE
    private var showsFans: Bool { false }
    #else
    private var showsFans: Bool { FanControl.shared.hasFans && isShown(ToolID.fans) }
    #endif

    private var showsBrightness: Bool { isShown(ToolID.brightness) && !Brightness.shared.monitors.isEmpty }

    private var hasNew: Bool {
        !NewMarks.shared.settingsOpened && NewMarks.shared.unseenTabs.contains { SettingsTab(rawValue: $0)?.isAvailable == true }
    }

    private var visibleTabs: [SettingsTab] {
        [.sound, .keyboard, .mouse, .windows, .dock, .finder, .games, .pet].filter { tab in registry.tools.contains { $0.tab == tab && isShown($0.id) } }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(id) },
            set: { shown in
                var ids = hidden
                if shown { ids.remove(id) } else { ids.insert(id) }
                hiddenList = ids.sorted().joined(separator: ",")
            }
        )
    }

    @ViewBuilder
    private func customizeRow(icon: Symbol, title: String, id: String) -> some View {
        Toggle(isOn: binding(id)) {
            Label {
                Text(title)
            } icon: {
                Image(icon).frame(width: 20)
            }
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if customizing {
                Text("Choose what this menu shows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !visibleTabs.isEmpty || isShown(ToolID.keepAwake) || showsBrightness || showsSpeedTest || showsFans || isShown(ToolID.temperatures) {
                        VStack(spacing: 0) {
                            if isShown(ToolID.keepAwake) {
                                if customizing {
                                    customizeRow(icon: .cupAndSaucer, title: TabTitle.keepAwake, id: ToolID.keepAwake)
                                } else {
                                    HStack(spacing: 0) {
                                        ToggleRow(
                                            icon: .cupAndSaucer,
                                            title: TabTitle.keepAwake,
                                            subtitle: keepAwake.statusText,
                                            hint: keepAwake.statusText,
                                            isOn: $keepAwake.isOn
                                        )
                                        Button { keepAwakeOpen.toggle() } label: {
                                            DisclosureChevron(isExpanded: keepAwakeOpen)
                                                .font(.system(size: 11, weight: .semibold))
                                                .animation(.snappy, value: keepAwakeOpen)
                                                .frame(width: 28, height: 38)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .help(Text("Display settings"))
                                        .accessibilityLabel(Text("Display settings"))
                                        .accessibilityValue(keepAwakeOpen ? Text("Expanded") : Text("Collapsed"))
                                    }
                                    if keepAwake.lidSleepStuck {
                                        HStack(spacing: 10) {
                                            Image(.exclamationmarkTriangleFill)
                                                .foregroundStyle(.orange)
                                                .frame(width: 28)
                                                .accessibilityHidden(true)
                                            Text("Your Mac still won’t sleep with the lid closed")
                                                .font(.caption)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                            Button("Let It Sleep") {
                                                NSApp.keyWindow?.close()
                                                keepAwake.letLidSleep()
                                            }
                                            .controlSize(.small)
                                            .glassButtons()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                    }
                                    VStack(spacing: 0) {
                                        if keepAwakeOpen { keepAwakeOptions.transition(.asymmetric(insertion: .opacity, removal: .identity)) }
                                    }
                                    .animation(.snappy, value: keepAwakeOpen)
                                }
                            }

                            if showsBrightness {
                                if customizing {
                                    customizeRow(icon: .sunMax, title: TabTitle.brightness, id: ToolID.brightness)
                                } else {
                                    BrightnessRow()
                                }
                            }

                            #if !APPSTORE
                            if showsSpeedTest {
                                if customizing {
                                    customizeRow(icon: .speedometer, title: TabTitle.speedTest, id: ToolID.speedTest)
                                } else {
                                    SpeedTestRow()
                                }
                            }
                            #endif

                            #if !APPSTORE
                            if showsFans {
                                if customizing {
                                    customizeRow(icon: .fan, title: TabTitle.fans, id: ToolID.fans)
                                } else {
                                    FanRow()
                                }
                            }
                            #endif

                            if isShown(ToolID.temperatures) {
                                if customizing {
                                    customizeRow(icon: .thermometerMedium, title: TabTitle.temperatures, id: ToolID.temperatures)
                                } else {
                                    TemperatureRow()
                                }
                            }

                            ForEach(Array(visibleTabs.enumerated()), id: \.element) { index, tab in
                                if index > 0 || isShown(ToolID.keepAwake) || showsBrightness || showsSpeedTest || showsFans || isShown(ToolID.temperatures) { groupDivider }
                                ForEach(registry.tools.filter { $0.tab == tab && isShown($0.id) }, id: \.id) { tool in
                                    if customizing {
                                        customizeRow(icon: tool.icon, title: tool.title, id: tool.id)
                                    } else {
                                        tool.settingsView.needs(tool.needs)
                                    }
                                }
                            }
                        }
                        .padding(6)
                        .glassCard()
                    }

                    if registry.needsPermission {
                        Button {
                            SettingsWindow.show(.permissions)
                        } label: {
                            Label("Permissions needed", symbol: .exclamationmarkTriangleFill)
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }

                    if FinderRestart.shared.isNeeded {
                        Button {
                            FinderRestart.shared.restart()
                        } label: {
                            Label("Restart Finder", symbol: .arrowClockwise)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .help(Text("Restart Finder once to bring back the right-click items"))
                    }
                }
                .background(GeometryReader { geo in
                    Color.clear.onChange(of: geo.size.height, initial: true) { contentHeight = geo.size.height }
                })
            }
            // A ScrollView has no natural height in an auto-sized window, so give it the measured one.
            .frame(height: min(contentHeight, maxRowsHeight))
            .scrollClipDisabled(contentHeight <= maxRowsHeight)
            .scrollBounceBehavior(.basedOnSize)
            // While a row grows or shrinks the rows and the frame are a moment out of step; .hidden would still show
            // a permanent scroller, so only a real overflow gets one.
            .scrollIndicators(contentHeight > maxRowsHeight ? .automatic : .never)

            HStack(spacing: 8) {
                if customizing {
                    Spacer(minLength: 8)
                    Button("Done") { customizing = false }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { SettingsWindow.show() } label: { Label("Settings…", symbol: .gearshape) }
                        .keyboardShortcut(",")
                        .help("Settings…")
                        .overlay(alignment: .topTrailing) { if hasNew { NewDot().padding(1) } }
                    Button { customizing = true } label: { Label("Customize…", symbol: .pencil) }
                        .help("Customize…")
                    Spacer(minLength: 8)
                    Button { NSApp.terminate(nil) } label: { Label("Quit", symbol: .power) }
                        .keyboardShortcut("q")
                        .help("Quit")
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(customizing ? .automatic : .circle)
            .fixedSize(horizontal: false, vertical: true)
            .glassButtons()

            updateFooter
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(width: 330)
        .onAppear { permissions.refresh() }
    }

    private var keepAwakeOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingTitle.display).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Display", selection: $keepAwake.keepsDisplayOn) {
                Text("Always on").tag(true)
                Text("Turns off as usual").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Button {
                NSApp.keyWindow?.close()
                KeepAwake.turnOffDisplay()
            } label: {
                Label("Turn off the display now", symbol: .display)
                    .frame(maxWidth: .infinity)
            }
            .glassButtons()
            Text("Your Mac keeps working. To bring the display back, move the mouse or press a key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 46)
        .padding(.trailing, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var groupDivider: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 4)
    }

    @ViewBuilder
    private var updateFooter: some View {
        #if !APPSTORE
        let updater = Updater.shared
        if case .available(let version) = updater.state {
            Button {
                Task { await updater.install() }
            } label: {
                Label("Update to \(version)", symbol: .arrowDownCircleFill)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        #endif
    }
}
