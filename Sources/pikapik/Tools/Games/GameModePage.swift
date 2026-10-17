import AppKit
import SwiftUI

struct GameModePage: View {
    @Bindable private var tool = GameModeTool.shared
    @State private var advanced = false
    @State private var safeguards = false

    var body: some View {
        Form {
            SettingsHeader(
                tab: .games,
                text: tool.game.map { String(localized: "Now playing: \($0.title)") } ?? String(localized: "Play without interruptions")
            )
            Section {
                GameModeArt(on: tool.isEnabled)
                tool.settingsView
            }
            Section {
                Group {
                    GameList(tool: tool)
                        .onAppear { tool.refreshSuggestions() }
                    ForEach(tool.suggestions, id: \.self) { key in
                        LabeledContent {
                            HStack {
                                Button("Ignore") { tool.dismiss(key) }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                Button("Add") { tool.confirm(key) }
                            }
                            .fixedSize()
                        } label: {
                            AppLabel(id: key, subtitle: Text("Looks like a game"))
                        }
                    }
                }
                .appDropZone("games", accepting: { GameModeTool.key($0) != nil }, textFiles: GameModeTool.processFiles) { tool.add($0) }
            } footer: {
                Text("You can also drag a game here from Finder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            FrameRateSettings(tool: tool)
            Section {
                DisclosureGroup(isExpanded: $advanced) {
                    EmptyView()
                } label: {
                    GameDisclosureLabel(title: String(localized: "More game settings"), detail: String(localized: "Fine-tune protection and explore your Mac’s shortcuts."), symbol: "slider.horizontal.3")
                }
                .disclosureGroupStyle(GameDisclosureStyle(contentSpacing: 0))
            }
            if advanced {
                SystemShortcutList(tool: tool)
                Section {
                    DisclosureGroup(isExpanded: $safeguards) {
                        Text("To leave a game, press \(CommandKeysTool.quit.text); to close its window, \(CommandKeysTool.close.text). ⌥⌘Esc always works.").font(.subheadline).foregroundStyle(.secondary)
                    } label: {
                        GameDisclosureLabel(title: String(localized: "Game safeguards"), detail: String(localized: "Closing the game, the pointer and display."), symbol: "shield", count: GameRule.allCases.count)
                    }
                    .disclosureGroupStyle(GameDisclosureStyle())
                    .settingAnchor(String(localized: "Game safeguards"))
                }
                if safeguards {
                    rules(Text("Closing the game"), [
                        Rule(.commandQ, String(localized: "The game doesn’t close"), ["⌘Q"]),
                        Rule(.commandW, String(localized: "The game window doesn’t close"), ["⌘W"]),
                    ], footer: Text("To leave a game, press \(CommandKeysTool.quit.text); to close its window, \(CommandKeysTool.close.text). ⌥⌘Esc always works."))
                    rules(Text("Apps"), [
                        Rule(.appSwitcher, String(localized: "Apps and windows don’t switch"), ["⌘Tab", key(27, "⌘`")]),
                        Rule(.hide, String(localized: "The game doesn’t hide"), ["⌘H", key(233, "⌘M")]),
                        Rule(.spotlight, String(localized: "Search doesn’t pop up"), [key(64, "⌘" + String(localized: "Space"))], subtitle: Text("Spotlight")),
                        Rule(.siri, String(localized: "Siri and voice typing don’t start"), [key(186, "🎤")]),
                        Rule(.launchpad, String(localized: "The app grid doesn’t open"), [key(173, "F4")], subtitle: Text("Launchpad")),
                    ])
                    rules(Text("Desktops"), [
                        Rule(.missionControl, String(localized: "The view of all windows doesn’t open"), [key(32, "⌃↑")], subtitle: Text("Mission Control")),
                        Rule(.appWindows, String(localized: "The view of the game’s windows doesn’t open"), [key(33, "⌃↓")], subtitle: Text("App Exposé")),
                        Rule(.showDesktop, String(localized: "The game doesn’t slide off the screen"), [key(36, "F11")], subtitle: Text("Show Desktop")),
                        Rule(.desktops, String(localized: "Desktops don’t switch"), [key(79, "⌃←"), key(81, "⌃→")]),
                        Rule(.desktopNumbers, String(localized: "Desktops don’t switch by number"), [key(118, "⌃1"), "…"]),
                    ])
                    rules(Text("Keyboard"), [
                        Rule(.emoji, String(localized: "Emoji don’t open"), [key(50, "⌃⌘" + String(localized: "Space"))]),
                        Rule(.lookUp, String(localized: "The dictionary doesn’t pop up"), [key(70, "⌃⌘D")], subtitle: Text("Look Up")),
                        Rule(.focusKeys, String(localized: "The keyboard stays in the game"), [key(60, "⌃" + String(localized: "Space")), key(12, "⌃F1"), "…"]),
                        Rule(.globe, String(localized: "🌐 shortcuts are paused"), ["🌐"]),
                    ])
                    rules(Text("Mouse and screen"), [
                        Rule(.controlClick, String(localized: "⌃-click works as a plain click"), ["⌃"]),
                        Rule(.shiftWheel, String(localized: "The wheel switches slots while you hold ⇧"), ["⇧"]),
                        Rule(.swipes, String(localized: "Gestures don’t leave the game")),
                        Rule(
                            .cursor, String(localized: "The pointer stays in the game"),
                            subtitle: Text("The Dock, menu bar and hot corners don’t pop up, and the pointer doesn’t slip onto another screen")
                        ),
                        Rule(.display, String(localized: "The screen stays on"), subtitle: Text("The display doesn’t dim or sleep while you play")),
                    ])
                }
            }
            RestoreDefaultsSection(
                message: String(localized: "These will turn off and go back to their default options: \(tool.title)"),
                isDefault: tool.isDefault,
                reset: tool.reset
            )
        }
        .formStyle(.grouped)
        .coordinateSpace(.named(SystemShortcutList.viewport))
        .settingsPage()
        .environment(\.inSettings, true)
        .onChange(of: SettingsWindow.model.highlight, initial: true) {
            let simple = [tool.title, String(localized: "Your games"), String(localized: "Show FPS"), String(localized: "Corner for FPS")]
            if let title = SettingsWindow.model.highlight, !simple.contains(title) {
                advanced = true
                if title == String(localized: "Game safeguards") || SettingsWindow.model.highlightedShortcut == nil && !GameShortcutGroup.allCases.contains(where: { $0.title == title }) && title != String(localized: "System keyboard shortcuts") { safeguards = true }
            }
        }
    }

    private func key(_ id: Int32, _ fallback: String) -> String {
        SystemShortcuts.shared.text(id) ?? fallback
    }

    private func rules(_ header: Text, _ rows: [Rule], footer: Text? = nil) -> some View {
        #if APPSTORE
        let rows = rows.filter { $0.rule != .cursor && ($0.rule.hotKeys.isEmpty || [.appSwitcher, .hide].contains($0.rule) || $0.rule.hotKeys.contains { SymbolicHotKeys.value($0) != nil }) }
        #endif
        return Section {
            ForEach(rows, id: \.rule) { row in
                VStack(spacing: 10) {
                    IllustrationRow { GameRuleArt(rule: row.rule, keys: row.keys, on: tool.rules.contains(row.rule)) }
                        .opacity(tool.isEnabled ? 1 : 0.5)
                    Toggle(isOn: Binding { tool.rules.contains(row.rule) } set: { if $0 { tool.rules.insert(row.rule) } else { tool.rules.remove(row.rule) } }) {
                        HStack(spacing: 12) {
                            RowLabel(Text(row.title), row.rule.detail.map { Text(verbatim: $0) })
                            Spacer(minLength: 0)
                            if !row.keys.isEmpty { KeyCaps(keys: row.keys, system: row.rule.hotKeys.isEmpty ? nil : SystemShortcuts.place(row.rule.hotKeys)) }
                        }
                    }
                }
                .settingAnchor(row.title)
            }
            .disabled(!tool.isEnabled)
        } header: {
            header
        } footer: {
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Rule {
    let rule: GameRule
    let title: String
    let keys: [String]
    let subtitle: Text?

    init(_ rule: GameRule, _ title: String, _ keys: [String] = [], subtitle: Text? = nil) {
        self.rule = rule
        self.title = title
        self.keys = keys
        self.subtitle = subtitle
    }
}

struct GameModeSettings: View {
    @Bindable var tool: GameModeTool

    var body: some View {
        ToggleRow(
            icon: tool.icon,
            title: tool.title,
            subtitle: Text("While you play, your Mac doesn’t pull you out of the game"),
            hint: tool.game.map { Text("Now playing: \($0.title)") } ?? Text("Your Mac doesn’t pull you out of a game"),
            help: Text("To leave a game, press \(CommandKeysTool.quit.text); to close its window, \(CommandKeysTool.close.text). ⌥⌘Esc always works."),
            isOn: $tool.isEnabled
        )
    }
}

struct GameModeArt: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let durations = [1.8, 0.9, 1.2, 0.8, 1.6, 1.7]
    private static let screen = CGSize(width: 196, height: 108)
    private static let bar = CGRect(x: 39, y: 23, width: 118, height: 22)

    var body: some View {
        IllustrationRow(loop: Self.durations) { tick in
            let step = reduceMotion ? 0 : tick % Self.durations.count
            let search = step == 1 || !on && step == 2
            let edge = step == 4
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            ArtTimeline { time in
                Stage {
                    ZStack {
                        GameScene(time: time ?? GameStory.start)
                        ArtDock(icon: 14)
                            .offset(y: !on && edge ? 40 : 72)
                        Capsule()
                            .fill(.white.opacity(0.85))
                            .frame(width: 44, height: 2)
                            .blur(radius: 1.5)
                            .offset(x: 30, y: Self.screen.height / 2 - 1)
                            .opacity(on && edge ? 1 : 0)
                        ZStack {
                            GameScene(time: time ?? GameStory.start).glassBackdrop(Self.bar)
                            ArtSpotlight(width: Self.bar.width, height: Self.bar.height)
                                .position(x: Self.bar.midX, y: Self.bar.midY)
                        }
                        .opacity(search ? (on ? 0.6 : 1) : 0)
                        .scaleEffect(search ? 1 : 0.9)
                        .blur(radius: on && !search ? 4 : 0)
                    }
                    .frame(width: Self.screen.width, height: Self.screen.height)
                    .clipShape(shape)
                    .overlay(shape.hairline(Color.primary.opacity(0.14)))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .position(x: 150, y: 64)
                    ArtCursor()
                        .cursor(at: (3...4).contains(step) ? CGPoint(x: 180, y: 115) : CGPoint(x: 176, y: 74))
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: step)
            }
        }
    }
}
