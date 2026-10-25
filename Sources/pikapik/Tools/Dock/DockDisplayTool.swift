import AppKit
import SwiftUI

/// Stops the Dock from following the pointer to another display with the Dock's own switch, which the Dock reads only when it starts.
@Observable
final class DockDisplayTool: Tool {
    let id = ToolID.dockDisplay
    let icon = Symbol.display2
    var title: String { SettingTitle.dockDisplay }
    let tab = SettingsTab.dock
    let needs: [Permission] = []

    var isActive: Bool { isEnabled }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: id)
            refresh()
        }
    }

    private static let dock = AppConstants.dockBundleID as CFString, key = "allow-display-switching" as CFString
    @ObservationIgnored private var displays: NSObjectProtocol?
    @ObservationIgnored private var settle: DispatchWorkItem?

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: id)
    }

    var settingsView: AnyView {
        AnyView(DockDisplaySettings(tool: self))
    }

    func refresh() {
        let on = isEnabled && MainCopy.canAct
        if Self.apply(on) { AnimationsTool.shared.restartDock() }
        let off = !isEnabled && MainCopy.canAct
        if off { MainDisplayControl.restore() }
        watchDisplays(off && MainDisplayControl.pending)
    }

    private func watchDisplays(_ watch: Bool) {
        guard watch else {
            if let displays { NotificationCenter.default.removeObserver(displays) }
            displays = nil
            settle?.cancel()
            settle = nil
            return
        }
        guard displays == nil else { return }
        displays = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.settle?.cancel()
            let work = DispatchWorkItem { self?.refresh() }
            self?.settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    static func uninstall() {
        if apply(false) { AnimationsTool.killall("Dock", wait: true) }
        MainDisplayControl.restore()
    }

    static func powerOff() -> Bool {
        apply(false)
    }

    private static func apply(_ on: Bool) -> Bool {
        CFPreferencesAppSynchronize(dock)
        return DockDisplaySwitch.apply(on, current: CFPreferencesCopyAppValue(key, dock) as? Bool) { value in
            CFPreferencesSetAppValue(key, value.map { $0 as CFBoolean }, dock)
            CFPreferencesAppSynchronize(dock)
        }
    }
}

struct DockDisplayArt: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let durations = [1.0, 1.1, 1.4, 1.2]

    var body: some View {
        IllustrationRow(loop: Self.durations) { tick in
            let step = reduceMotion ? 2 : tick % Self.durations.count
            let jumped = !on && step >= 2
            Stage {
                ArtMonitor(glow: 0.8, dock: false) { dock(shown: !jumped) }
                    .position(x: 84, y: 64)
                ArtMonitor(glow: 0.8, dock: false) { dock(shown: jumped) }
                    .position(x: 216, y: 64)
                ArtCursor()
                    .cursor(at: step == 0 ? CGPoint(x: 104, y: 46) : CGPoint(x: 222, y: 67))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: step)
        }
    }

    @ViewBuilder private func dock(shown: Bool) -> some View {
        if shown {
            ArtDock(appDot: false, icon: 7)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct DockDisplaySettings: View {
    @Bindable var tool: DockDisplayTool
    @Environment(\.inSettings) private var inSettings

    var body: some View {
        if inSettings { DockDisplayArt(on: tool.isEnabled) }
        ToggleRow(
            icon: tool.icon,
            title: tool.title,
            subtitle: Text("To move it, make another display the main one"),
            hint: Text("To move it, make another display the main one"),
            help: Text("The Dock no longer jumps to another display when the pointer hits its bottom edge, however fast you move. To move the Dock, make another display the main one. Turning this on or off restarts the Dock."),
            isOn: $tool.isEnabled
        )
        if inSettings { MainDisplayRow(enabled: tool.isEnabled) }
    }
}

private struct MainDisplayRow: View {
    let enabled: Bool
    @State private var screens = MainDisplayControl.screens

    var body: some View {
        Group {
            if screens.count > 1 {
                LabeledContent {
                    Picker(selection: Binding(get: { screens.first { $0.origin == .zero }?.id }, set: { id in screens.first { $0.id == id }.map(change) })) {
                        ForEach(screens) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    } label: { Text("Main display") }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!enabled)
                } label: {
                    RowLabel(Text("Main display"), Text("The Dock goes with it. Turning the switch off puts the displays back as they were"))
                }
                .settingAnchor(SettingTitle.mainDisplay)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = MainDisplayControl.screens }
    }

    private func change(to screen: MainDisplayControl.Screen) {
        MainDisplayControl.makeMain(screen)
        screens = MainDisplayControl.screens
    }
}

enum MainDisplayControl {
    struct Screen: Identifiable {
        let id: CGDirectDisplayID
        let uuid: String
        let name: String
        let origin: CGPoint
    }

    private static let key = "dock-display-arrangements", oldKey = "dock-display-origins"

    static var screens: [Screen] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid) as String? else { return nil }
            return Screen(id: id, uuid: text, name: screen.localizedName, origin: CGDisplayBounds(id).origin)
        }
    }

    static func makeMain(_ target: Screen) {
        let now = screens
        guard let origins = MainDisplay.origins(now.map { (uuid: $0.uuid, origin: $0.origin) }), let moved = MainDisplay.moved(origins, to: target.uuid) else { return }
        let before = journal
        journal = MainDisplay.remembered(before, now: origins, main: target.uuid)
        if !apply(moved, to: now) { journal = before }
    }

    static func restore() {
        let saved = journal
        guard !saved.isEmpty else { return }
        let now = screens
        guard let origins = MainDisplay.origins(now.map { (uuid: $0.uuid, origin: $0.origin) }) else { return }
        let result = MainDisplay.restored(saved, now: origins)
        if let target = result.write, !apply(target, to: now) { return }
        journal = result.journal
    }

    static var pending: Bool { !journal.isEmpty }

    private static var journal: [String: MainDisplay.Saved] {
        get {
            let defaults = UserDefaults.standard
            return MainDisplay.journal(defaults.dictionary(forKey: key), old: defaults.dictionary(forKey: oldKey) as? [String: [Double]])
        }
        set {
            let defaults = UserDefaults.standard
            if newValue.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(MainDisplay.stored(newValue), forKey: key) }
            defaults.removeObject(forKey: oldKey)
        }
    }

    private static func apply(_ origins: [String: CGPoint], to screens: [Screen]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for screen in screens {
            guard let point = origins[screen.uuid], CGConfigureDisplayOrigin(config, screen.id, Int32(point.x), Int32(point.y)) == .success else {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
