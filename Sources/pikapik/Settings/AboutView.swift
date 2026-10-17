import AppKit
import SwiftUI

struct AboutView: View {
    private static let github = Bundle.main.url(forResource: "github", withExtension: "svg").flatMap { NSImage(contentsOf: $0) }
    #if APPSTORE
    private static let source = "https://github.com/dev-pikapik/pikapik/tree/main/Sources/pikapik"
    private static let edition = "Mac%20App%20Store"
    #else
    private static let source = "https://github.com/dev-pikapik/pikapik"
    private static let edition = "Website%20%2F%20GitHub%20%2F%20Homebrew"
    #endif

    private static var whatsNew: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let page = code != "en" && Language.codes.contains(code) ? "README.\(code).md" : "README.md"
        return "https://github.com/dev-pikapik/pikapik/blob/main/docs/whats-new/\(page)"
    }

    #if !APPSTORE
    @Bindable private var updater = Updater.shared
    #endif
    private let info = Bundle.main.infoDictionary ?? [:]
    private var version: String {
        "\(info["CFBundleShortVersionString"] ?? "")"
    }
    private var icon: NSImage {
        _ = IconStyle.shared.theme
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        Form {
            SettingsHeader(tab: .about, title: "pikapik", text: String(localized: "Small tools that make your Mac nicer to use"), appIcon: icon)

            #if APPSTORE
            Section { LabeledContent { EmptyView() } label: { RowLabel(Text("Version \(version)")) } }
            #else
            Section("Updates") {
                let autoTitle = String(localized: "Check for updates automatically")
                Toggle(autoTitle, isOn: $updater.checksAutomatically)
                    .settingAnchor(autoTitle)
                LabeledContent {
                    if case .available(let version) = updater.state {
                        Button("Update to \(version)", systemImage: "arrow.down.circle") { Task { await updater.install() } }
                            .buttonStyle(.borderedProminent)
                            .accessibilityElement(children: .contain)
                    } else {
                        Button("Check Now", systemImage: "arrow.triangle.2.circlepath") { Task { await updater.check() } }
                            .disabled(updater.state == .checking || updater.state == .installing)
                            .accessibilityElement(children: .contain)
                    }
                } label: {
                    RowLabel(Text("Version \(version)"), updater.state.title.map { Text($0) })
                        .textSelection(.enabled)
                }
            }
            #endif

            #if APPSTORE
            TipJarSection()
            #endif

            Section {
                link("GitHub", Self.source, symbol: "chevron.left.forwardslash.chevron.right", color: .gray, template: Self.github)
                link(String(localized: "What’s New"), Self.whatsNew, symbol: "newspaper.fill", color: .blue)
                link(String(localized: "Report a Problem"), "https://github.com/dev-pikapik/pikapik/issues/new?template=bug_report.yml&edition=\(Self.edition)&version=\(version)", symbol: "ladybug.fill", color: .red)
                link(String(localized: "License (MIT)"), "https://github.com/dev-pikapik/pikapik/blob/main/LICENSE", symbol: "doc.text.fill", color: .green)
            } footer: {
                VStack(spacing: 4) {
                    Text(verbatim: info["NSHumanReadableCopyright"] as? String ?? "")
                    #if !APPSTORE
                    CoffeeLine()
                    #endif
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            #if !APPSTORE
            RestoreDefaultsSection(
                message: String(localized: "pikapik will check for updates automatically again."),
                isDefault: updater.checksAutomatically
            ) {
                updater.checksAutomatically = true
            }
            #endif
        }
        .formStyle(.grouped)
        .settingsPage()
    }

    private func link(_ title: String, _ url: String, symbol: String, color: Color, template: NSImage? = nil) -> some View {
        Link(destination: URL(string: url)!) {
            LabeledContent {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            } label: {
                HStack(spacing: 10) {
                    SectionIcon(symbol: symbol, color: color, size: SettingsTab.iconSize, template: template)
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingAnchor(title)
    }
}

#if !APPSTORE
private struct CoffeeLine: View {
    static let coffeeTitle = String(localized: "Buy me a coffee")
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text("Made with care")
            Text(verbatim: "·")
                .accessibilityHidden(true)
            Link(destination: URL(string: "https://buymeacoffee.com/pikapik")!) {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("Buy me a coffee")
                }
                .foregroundStyle(hovering ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovering { NSCursor.pop() }
            }
            .settingAnchor(Self.coffeeTitle)
        }
    }
}
#endif
