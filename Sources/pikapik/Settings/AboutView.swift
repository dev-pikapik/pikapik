import AppKit
import SwiftUI

struct AboutView: View {
    private static let github = Bundle.main.url(forResource: "github", withExtension: "svg").flatMap { NSImage(contentsOf: $0) }
    #if APPSTORE
    private static let source = "\(AppConstants.githubRepoURL)/tree/main/Sources/pikapik"
    private static let edition = "Mac%20App%20Store"
    #else
    private static let source = AppConstants.githubRepoURL
    private static let edition = "Website%20%2F%20GitHub%20%2F%20Homebrew"
    #endif

    private static var whatsNew: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let page = code != "en" && Language.codes.contains(code) ? "README.\(code).md" : "README.md"
        return "\(AppConstants.githubRepoURL)/blob/main/docs/whats-new/\(page)"
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
            SettingsHeader(tab: .about, title: AppConstants.appName, text: String(localized: "Small tools that make your Mac nicer to use"), appIcon: icon)

            #if APPSTORE
            Section { LabeledContent { EmptyView() } label: { RowLabel(Text("Version \(version)")) } }
            #else
            Section("Updates") {
                Toggle(SettingTitle.checkForUpdatesAutomatically, isOn: $updater.checksAutomatically)
                    .settingAnchor(SettingTitle.checkForUpdatesAutomatically)
                LabeledContent {
                    if case .available(let version) = updater.state {
                        Button("Update to \(version)", symbol: .arrowDownCircle) { Task { await updater.install() } }
                            .buttonStyle(.borderedProminent)
                            .accessibilityElement(children: .contain)
                    } else {
                        Button("Check Now", symbol: .arrowTriangle2Circlepath) { Task { await updater.check() } }
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
                link("GitHub", Self.source, symbol: .chevronLeftForwardslashChevronRight, color: .gray, template: Self.github)
                link(SettingTitle.whatsNew, Self.whatsNew, symbol: .newspaperFill, color: .blue)
                link(SettingTitle.reportAProblem, "\(AppConstants.githubRepoURL)/issues/new?template=bug_report.yml&edition=\(Self.edition)&version=\(version)", symbol: .ladybugFill, color: .red)
                link(SettingTitle.licenseMIT, "\(AppConstants.githubRepoURL)/blob/main/LICENSE", symbol: .docTextFill, color: .green)
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

    private func link(_ title: String, _ url: String, symbol: Symbol, color: Color, template: NSImage? = nil) -> some View {
        Link(destination: URL(string: url)!) {
            LabeledContent {
                Image(.arrowUpForward)
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text("Made with care")
            Text(verbatim: "·")
                .accessibilityHidden(true)
            Link(destination: URL(string: AppConstants.buyMeACoffeeURL)!) {
                HStack(spacing: 4) {
                    Image(.cupAndSaucerFill)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(SettingTitle.buyMeACoffee)
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
            .settingAnchor(SettingTitle.buyMeACoffee)
        }
    }
}
#endif
