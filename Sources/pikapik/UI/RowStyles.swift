import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RowLabel: View {
    let title: Text
    var subtitle: Text?
    var row: String?

    init(_ title: Text, _ subtitle: Text? = nil, row: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let row {
                HStack(spacing: 6) {
                    title
                    NewRowTag(row: row)
                }
            } else {
                title
            }
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CenteredLabeledContentStyle: LabeledContentStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .opacity(isEnabled ? 1 : 0.5)
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

struct CenteredSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .opacity(isEnabled ? 1 : 0.5)
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct KeyCap: View {
    let symbol: String

    var body: some View {
        Text(verbatim: symbol)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .frame(minWidth: 24, minHeight: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}

struct KeyCaps: View {
    let keys: [String]
    var system: SystemShortcuts.Place?
    @State private var showsHint = false

    var body: some View {
        if let system {
            Button {
                SystemShortcuts.open(system) { showsHint = true }
            } label: { caps }
                .buttonStyle(CapsButtonStyle())
                .help(Text("Change in System Settings"))
                .accessibilityLabel(Text(verbatim: shown.map { $0.isEmpty ? String(localized: "Off") : $0 }.joined(separator: ", ")))
                .accessibilityHint(system.hint.map { Text($0) } ?? Text("Change in System Settings"))
                .popover(isPresented: $showsHint, arrowEdge: .bottom) {
                    if let guide = system.guide {
                        guide.frame(width: 340).padding(12)
                    } else {
                        Text(system.hint ?? "")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 320, alignment: .leading)
                            .padding(12)
                    }
                }
        } else {
            caps.accessibilityHidden(true)
        }
    }

    private var shown: [String] {
        let live = keys.filter { !$0.isEmpty }
        return !keys.isEmpty && live.allSatisfy { $0 == "…" } ? [""] : live
    }

    private var caps: some View {
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, shortcut in
                if shortcut.isEmpty {
                    Text("Off").foregroundStyle(.secondary)
                } else if shortcut == "…" {
                    Text(verbatim: shortcut).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 2) {
                        ForEach(Array(Self.caps(shortcut).enumerated()), id: \.offset) { KeyCap(symbol: $0.element) }
                    }
                }
            }
        }
        .fixedSize()
    }

    static func caps(_ shortcut: String) -> [String] {
        let modifiers = shortcut.prefix { "⌃⌥⇧⌘🌐".contains($0) }
        let key = shortcut.dropFirst(modifiers.count)
        return modifiers.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }
}

struct KeyLabel: View {
    var keys: [String] = []
    var system: SystemShortcuts.Place?
    let title: Text
    var subtitle: Text?

    var body: some View {
        HStack(spacing: 12) {
            if !keys.isEmpty { KeyCaps(keys: keys, system: system) }
            RowLabel(title, subtitle)
        }
    }
}

extension View {
    func noticeBar() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

struct AppRowLabel<Trailing: View>: View {
    let icon: NSImage?
    let name: String
    var running = false
    let byline: String
    var minNameWidth: CGFloat?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            } else {
                SectionIcon(symbol: "terminal", color: .gray, size: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .lineLimit(1)
                    if running {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .help(Text("Open now"))
                            .accessibilityLabel(Text("Open now"))
                    }
                }
                if !byline.isEmpty {
                    Text(byline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: minNameWidth, alignment: .leading)
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())
    }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

struct OpenWithRow: View {
    let title: String
    let formats: [(name: String, types: [UTType])]
    @Bindable var apps: DefaultApps
    @Namespace private var chips
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let groups = groups
        VStack(alignment: .leading, spacing: 8) {
            RowLabel(Text(verbatim: title))
            ForEach(groups, id: \.app) { group in
                let types = group.formats.flatMap(\.types)
                HStack(alignment: .top, spacing: 10) {
                    AppMenu(header: Text("Open these formats with"), owner: group.app, choices: choices(for: types), choose: { apps.open(types, with: $0) }) { hover in
                        AppName(app: group.app, chevron: choices(for: types).contains { $0 != group.app }, hover: hover)
                    }
                    ChipFlow {
                        ForEach(group.formats, id: \.name) { format in
                            AppMenu(header: Text("Open \(format.name) with"), owner: group.app, choices: choices(for: format.types), choose: { apps.open(format.types, with: $0) }) { hover in
                                FormatChip(name: format.name, ours: group.app == apps.target, hover: hover)
                            }
                            .accessibilityLabel(Text(verbatim: format.name))
                            .accessibilityValue(Text(verbatim: AppName.name(of: group.app)))
                            .matchedGeometryEffect(id: format.name, in: chips)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            if apps.busy {
                Text("macOS will ask about each format.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: groups.map { "\($0.app?.path ?? "")\($0.formats.map(\.name))" })
        .disabled(apps.busy)
        .settingAnchor(title)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in apps.refresh() }
    }

    /// pikapik first, then the other apps by name.
    private func choices(for types: [UTType]) -> [URL] {
        apps.choices(for: types).sorted { a, b in
            a == apps.target || b != apps.target && AppName.name(of: a).localizedStandardCompare(AppName.name(of: b)) == .orderedAscending
        }
    }

    private var groups: [(app: URL?, formats: [(name: String, types: [UTType])])] {
        let formats = formats.filter { !$0.types.isEmpty }
        let owners = formats.map { apps.owner(of: $0.types) }
        var order: [URL?] = []
        for owner in owners where !order.contains(owner) { order.append(owner) }
        let groups = order.map { app in (app: app, formats: zip(formats, owners).filter { $0.1 == app }.map(\.0)) }
        func rank(_ index: Int) -> (Int, Int, Int) {
            let app = groups[index].app
            return (app == apps.target ? 0 : app == nil ? 2 : 1, -groups[index].formats.count, index)
        }
        return groups.indices.sorted { rank($0) < rank($1) }.map { groups[$0] }
    }
}

/// "Open with" menu like Finder's: the app that opens the formats now is checked, choosing another one moves them.
private struct AppMenu<Label: View>: View {
    let header: Text
    let owner: URL?
    let choices: [URL]
    let choose: (URL) -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hover = false

    var body: some View {
        Menu {
            Section {
                Picker(selection: Binding(get: { owner }, set: { app in if let app, app != owner, MainCopy.canAct { choose(app) } })) {
                    ForEach(choices, id: \.self) { app in
                        SwiftUI.Label { Text(verbatim: AppName.name(of: app)) } icon: { Image(nsImage: AppName.icon(of: app, size: 16)) }
                            .tag(Optional(app))
                    }
                } label: { header }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { header }
        } label: {
            label(hover)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
    }
}

private struct AppName: View {
    let app: URL?
    let chevron: Bool
    let hover: Bool

    static func name(of app: URL?) -> String {
        app.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards]) } ?? String(localized: "No app")
    }

    static func icon(of app: URL, size: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let app {
                Image(nsImage: Self.icon(of: app, size: 16))
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .frame(width: 16, height: 16)
            }
            Text(verbatim: Self.name(of: app))
                .lineLimit(1)
                .truncationMode(.middle)
            if chevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(chevron && hover ? .primary : .secondary)
        .frame(width: 150, height: 22, alignment: .leading)
        .contentShape(Rectangle())
        .help(Self.name(of: app))
    }
}

private struct FormatChip: View {
    let name: String
    let ours: Bool
    let hover: Bool

    var body: some View {
        Text(verbatim: name)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(ours ? Color.accentColor.opacity(hover ? 0.32 : 0.2) : Color.primary.opacity(hover ? 0.14 : 0.07), in: Capsule())
            .contentShape(Capsule())
    }
}

struct ChipFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = place(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var point = CGPoint.zero
        var line: CGFloat = 0
        return subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            if point.x > 0, point.x + size.width > width {
                point = CGPoint(x: 0, y: point.y + line + 4)
                line = 0
            }
            defer { point.x += size.width + 4 }
            line = max(line, size.height)
            return CGRect(origin: point, size: size)
        }
    }
}
