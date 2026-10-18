import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerPage: View {
    static let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/pikapik Player.app")
    private static let license = Bundle.main.url(forResource: "Player Licenses", withExtension: "txt")
    private static let source = AppConstants.githubReleasesURL
    private static let videos = DefaultApps(types: PlayerFormats.videoTypes, target: helper, previousKey: PreferenceKey.playerVideoPreviousApps)
    private static let songs = DefaultApps(types: PlayerFormats.musicTypes, target: helper, previousKey: PreferenceKey.playerMusicPreviousApps, fallback: "com.apple.Music")
    private static let pictures = DefaultApps(types: ImageFormats.types, target: helper, previousKey: PreferenceKey.playerImagePreviousApps, fallback: ImageFormats.previewApp)

    var body: some View {
        Form {
            SettingsHeader(tab: .player, text: String(localized: "MKV, FLAC, RAW and other videos, songs and pictures in their own window"))
            Section {
                Button(action: open) { Text("Open Video…").frame(minWidth: 140) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .settingAnchor(SettingTitle.openVideo)
            }
            Section {
                DefaultAppToggle(title: SettingTitle.openVideosInPikapik, formats: Self.formats(PlayerFormats.video), apps: Self.videos)
                DefaultAppToggle(title: SettingTitle.openMusicInPikapik, formats: Self.formats(PlayerFormats.music), apps: Self.songs)
                DefaultAppToggle(title: SettingTitle.openPicturesInPikapik, formats: Self.formats(ImageFormats.all), apps: Self.pictures)
            }
            Section {
                if let license = Self.license {
                    row(SettingTitle.playerLicenses, symbol: .docTextFill, color: .green) { NSWorkspace.shared.open(license) }
                }
                row(SettingTitle.sourceCode, symbol: .chevronLeftForwardslashChevronRight, color: .gray) { NSWorkspace.shared.open(Self.source) }
            }
        }
        .formStyle(.grouped)
    }

    private static func formats(_ list: [(name: String, extensions: [String])]) -> [(name: String, types: [UTType])] {
        list.map { ($0.name, PlayerFormats.types(of: $0.extensions)) }
    }

    private func row(_ title: String, symbol: Symbol, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent {
                Image(.arrowUpRight)
                    .foregroundStyle(.secondary)
            } label: {
                HStack(spacing: 10) {
                    SectionIcon(symbol: symbol, color: color, size: SettingsTab.iconSize)
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingAnchor(title)
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = PlayerFormats.extensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        NSWorkspace.shared.open(panel.urls, withApplicationAt: Self.helper, configuration: NSWorkspace.OpenConfiguration())
    }
}
