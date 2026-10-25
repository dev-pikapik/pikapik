import AppKit
import SwiftUI

@Observable
final class TrashWatchTool: Tool {
    static let shared = TrashWatchTool()

    let id = ToolID.trashWatch
    let icon = Symbol.trash
    var title: String { SettingTitle.trashWatch }
    var tab: SettingsTab { .uninstaller }
    var needs: [Permission] { [.fullDisk] }
    private(set) var isActive = false

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: id)
            refresh()
        }
    }

    @ObservationIgnored private var watcher: TrashWatcher?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: id)
    }

    var settingsView: AnyView {
        AnyView(TrashWatchSettings(tool: self))
    }

    func refresh() {
        watcher?.stop()
        watcher = nil
        if isEnabled, MainCopy.canAct, Permissions.shared.fileAccess {
            watcher = TrashWatcher { urls in MainActor.assumeIsolated { UninstallerModel.shared.offer(urls) } }
        }
        isActive = watcher != nil
    }
}

private struct TrashWatchSettings: View {
    @Bindable var tool: TrashWatchTool
    @Environment(\.inSettings) private var inSettings

    var body: some View {
        if inSettings { TrashWatchArt(on: tool.isEnabled) }
        ToggleRow(
            icon: tool.icon,
            title: tool.title,
            subtitle: Text("Nothing is removed until you choose"),
            isOn: $tool.isEnabled
        )
    }
}
