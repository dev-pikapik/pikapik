import AppKit
import Carbon
import SwiftUI

#if APPSTORE
struct LayoutFixServiceSettings: View {
    @Bindable var tool: LayoutFixTool
    @Environment(\.inSettings) private var inSettings
    @State private var hovering = false

    var body: some View {
        if inSettings {
            LayoutFixArt(on: true, service: tool.fixesAsYouType ? nil : LayoutFixService.title)
            RowLabel(Text(tool.title), Text(LayoutFixService.hint))
                .settingAnchor(tool.title)
            let selectedTitle = String(localized: "Fix the selected text")
            let selectedSub = String(localized: "Select the text, then press these keys")
            Toggle(isOn: $tool.isEnabled) {
                Group {
                    if tool.isEnabled {
                        ShortcutLabel(
                            shortcut: $tool.shortcut,
                            standard: LayoutFixTool.standard,
                            title: Text(selectedTitle),
                            subtitle: Text(selectedSub),
                            others: []
                        )
                    } else {
                        KeyLabel(keys: [tool.shortcut.text], title: Text(selectedTitle), subtitle: Text(selectedSub))
                    }
                }
                .settingAnchor(selectedTitle)
            }
            .needs([.accessibility])
            Toggle(isOn: $tool.fixesAsYouType) {
                KeyLabel(keys: [String(localized: "Space")], title: Text("Fix words as you type"), subtitle: Text("When you press Space or Return"))
            }
            .settingAnchor(String(localized: "Fix words as you type"))
            .help(Text("Press \(tool.shortcut.text) right after a fix to undo it. That word won’t be fixed again."))
            .needs([.accessibility])
            if tool.fixesAsYouType {
                LayoutFixNotes(tool: tool)
                AppExclusions(title: String(localized: "Don’t fix text in these apps"), apps: $tool.excluded, isEnabled: tool.fixesAsYouType)
            }
        } else {
            Button { SettingsWindow.show(.keyboard) } label: {
                HStack(spacing: 10) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tool.isActive ? Color.white : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(tool.isActive ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title).font(.body).lineLimit(2)
                        Group {
                            if tool.fixesAsYouType, tool.isActive {
                                Text("Fixed when you press Space")
                            } else if tool.isActive {
                                Text("Press \(tool.shortcut.text) to fix")
                            } else {
                                Text("In the Services menu")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if tool.isActive, tool.isEnabled { KeyCaps(keys: [tool.shortcut.text]) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if hovering { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.fill.quaternary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}
#else
struct LayoutFixSettings: View {
    @Bindable var tool: LayoutFixTool
    @Environment(\.inSettings) private var inSettings

    var body: some View {
        if inSettings { LayoutFixArt(on: tool.isEnabled) }
        ToggleRow(
            icon: tool.icon,
            title: tool.title,
            subtitle: Text("And the keyboard switches to the right language"),
            hint: tool.fixesAsYouType ? Text("Fixed when you press Space") : Text("Press \(tool.shortcut.text) to fix"),
            help: Text("Press \(tool.shortcut.text) right after a fix to undo it. That word won’t be fixed again."),
            keys: [tool.shortcut.text],
            isOn: $tool.isEnabled
        )
        if inSettings {
            Toggle(isOn: $tool.fixesAsYouType) {
                KeyLabel(keys: [String(localized: "Space")], title: Text("Fix words as you type"), subtitle: Text("When you press Space or Return"))
            }
            .disabled(!tool.isEnabled)
            .settingAnchor(String(localized: "Fix words as you type"))
            ShortcutLabel(
                shortcut: $tool.shortcut,
                standard: LayoutFixTool.standard,
                title: Text("Fix the last word or selected text"),
                subtitle: Text("Press again for other layouts. Right after a fix, it undoes it."),
                others: []
            )
            .disabled(!tool.isEnabled)
            .settingAnchor(String(localized: "Fix the last word or selected text"))
            LayoutFixNotes(tool: tool)
        }
        AppExclusions(title: String(localized: "Don’t fix text in these apps"), apps: $tool.excluded, isEnabled: tool.isEnabled)
    }
}
#endif

private struct LayoutFixNotes: View {
    let tool: LayoutFixTool

    var body: some View {
        if !tool.ignored.isEmpty {
            LabeledContent {
                Button("Clear") { tool.ignored = [] }
            } label: {
                RowLabel(Text("Words left as you typed them"), Text(verbatim: tool.ignored.joined(separator: ", ")))
            }
        }
        #if APPSTORE
        if KeyboardLayouts.all.count < 2 {
            HStack(spacing: 12) {
                Text("This works when you have two or more keyboard layouts")
                Spacer(minLength: 0)
                Button("Keyboard Settings…") { NSWorkspace.shared.open(Shortcut.keyboardSettings) }
            }
            .noticeBar()
        }
        #else
        AddLayoutNotice()
        #endif
    }
}

#if !APPSTORE
private struct AddLayoutNotice: View {
    @State private var added = 0
    @State private var failed = false

    var body: some View {
        if KeyboardLayouts.all.count < 2 {
            let choices = KeyboardLayouts.addable()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("This works when you have two or more keyboard layouts")
                    Spacer(minLength: 0)
                    if choices.isEmpty || failed {
                        Button("Keyboard Settings…") { NSWorkspace.shared.open(Shortcut.keyboardSettings) }
                    }
                    if !choices.isEmpty {
                        Menu("Add a Layout") {
                            ForEach(choices, id: \.self) { source in
                                Button(KeyboardLayouts.string(source, kTISPropertyLocalizedName) ?? "") {
                                    failed = !KeyboardLayouts.enable(source)
                                    added += 1
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
                if failed {
                    Text("Couldn’t add the layout. Use Keyboard Settings instead.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .noticeBar()
            .id(added)
        }
    }
}
#endif
