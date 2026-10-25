import Foundation

enum Lifecycle {
    enum Moment: String, CaseIterable {
        case start, handOver, quit, powerOff, uninstall
    }

    enum Cell {
        case run(@MainActor () -> Void)
        #if !APPSTORE
        case dock(@MainActor (DockHost) -> Bool)
        case restartDock
        #endif
        case byTools
        case called(String)
        case none(String)
    }

    struct Row {
        let owner: String
        let changes: String?
        let cells: [Moment: Cell]
    }

    @MainActor static let rows: [Row] = {
        var rows: [Row] = []
        #if !APPSTORE
        rows += [
            Row(owner: "TextFocus", changes: "AXManualAccessibility or AXEnhancedUserInterface in Chromium and Electron apps", cells: [
                .start: .run { TextFocus.putBackAfterCrash() },
                .handOver: .run { TextFocus.unwatch() },
                .quit: .run { TextFocus.unwatch() },
                .powerOff: .none("those apps quit with the session, and quit puts back right after"),
                .uninstall: .none("the switch lives only as long as each app"),
            ]),
            Row(owner: "DesktopIcons", changes: "WindowManager StandardHideDesktopIcons or HideDesktop", cells: [
                .start: .run { DesktopIconsTool.putBack() },
                .handOver: .run { DesktopIconsTool.putBack() },
                .quit: .run { DesktopIconsTool.putBack() },
                .powerOff: .run { DesktopIconsTool.putBack() },
                .uninstall: .called("DesktopIconsTool.putBack()"),
            ]),
        ]
        #endif
        rows += [
            Row(owner: "ToolRegistry", changes: nil, cells: [
                .start: .run { ToolRegistry.shared.refresh() },
                .handOver: .run { ToolRegistry.shared.refresh() },
                .quit: .run { ToolRegistry.shared.refresh() },
            ]),
            Row(owner: "Permissions", changes: nil, cells: [
                .start: .run { Permissions.shared.checkSystemAudio() },
            ]),
            Row(owner: "SettingsSync", changes: nil, cells: [
                .start: .run { SettingsSync.shared.refresh() },
                .handOver: .run { SettingsSync.shared.refresh() },
                .quit: .run { SettingsSync.shared.refresh() },
            ]),
            Row(owner: "Brightness", changes: "display gamma while a monitor is dimmed below its own range", cells: [
                .start: .run { Brightness.shared.refresh() },
                .handOver: .run { Brightness.shared.release() },
                .quit: .run { Brightness.shared.release() },
                .powerOff: .none("macOS puts the gamma back when pikapik quits, right after"),
                .uninstall: .none("the gamma lasts only while pikapik runs"),
            ]),
            Row(owner: "KeepAwake", changes: "pmset disablesleep while the lid is closed", cells: [
                .start: .run {
                    KeepAwake.shared.resume()
                    KeepAwake.shared.restoreLidSleepIfNeeded()
                },
                .handOver: .run { KeepAwake.shared.suspend() },
                .quit: .called("KeepAwake.shared.handOff()"),
                .powerOff: .none("quit hands off right after"),
                .uninstall: .called("KeepAwake.shared.restoreLidSleepIfNeeded()"),
            ]),
        ]
        #if !APPSTORE
        rows += [
            Row(owner: "FanControl", changes: "fan speeds set through the root helper", cells: [
                .start: .none("FanControl.start() at launch"),
                .handOver: .run { FanControl.shared.handOff() },
                .quit: .run { FanControl.shared.handOff() },
                .powerOff: .none("quit hands off right after"),
                .uninstall: .called("FanControl.putBackServices()"),
            ]),
            Row(owner: "Updater", changes: nil, cells: [
                .start: .run { Updater.shared.resume() },
                .handOver: .run { Updater.shared.pause() },
                .quit: .run { Updater.shared.pause() },
            ]),
        ]
        #endif
        rows += [
            Row(owner: "GameMode", changes: "system shortcuts turned off for a game", cells: [
                .start: .none("leave() at the next app switch clears leftovers"),
                .handOver: .run { GameModeTool.shared.leave() },
                .quit: .run { GameModeTool.shared.leave() },
                .powerOff: .none("quit runs leave() right after"),
                .uninstall: .called("HotKeyTrace().restore()"),
            ]),
        ]
        #if APPSTORE
        rows += [
            Row(owner: "DockEdges", changes: nil, cells: [
                .handOver: .run { DockEdges.restore() },
                .quit: .run { DockEdges.restore() },
                .uninstall: .called("DockEdges.restore()"),
            ]),
        ]
        #else
        rows += [
            Row(owner: "DockEdges", changes: "com.apple.dock wvous-*-corner and autohide-delay held by a game", cells: [
                .start: .none("GameModeTool.leave() schedules restoreSoon()"),
                .handOver: .run { DockEdges.restore() },
                .quit: .run { DockEdges.restore() },
                .powerOff: .dock { DockEdges.restore($0); return false },
                .uninstall: .called("DockEdges.restore()"),
            ]),
            Row(owner: "HotCorners", changes: "com.apple.dock wvous-*-corner picked on the Games page", cells: [
                .start: .none("the pick stays until the next stop"),
                .handOver: .run { HotCorners.putBackAll() },
                .quit: .run { HotCorners.putBackAll() },
                .powerOff: .dock { HotCorners.putBackAll($0); return false },
                .uninstall: .called("HotCorners.putBackAll()"),
            ]),
            Row(owner: "Animations", changes: "Dock, Finder and global animation keys, and Dock autohide", cells: [
                .start: .byTools,
                .handOver: .byTools,
                .quit: .called("AnimationsTool.shared.willQuit()"),
                .powerOff: .dock { _ in AnimationsTool.shared.powerOff() },
                .uninstall: .called("AnimationsTool.uninstall()"),
            ]),
            Row(owner: "DockDisplay", changes: "com.apple.dock allow-display-switching", cells: [
                .start: .byTools,
                .handOver: .byTools,
                .quit: .byTools,
                .powerOff: .dock { _ in DockDisplayTool.powerOff() },
                .uninstall: .called("DockDisplayTool.uninstall()"),
            ]),
            Row(owner: "KeyRepeat", changes: "NSGlobalDomain ApplePressAndHoldEnabled", cells: [
                .start: .byTools,
                .handOver: .byTools,
                .quit: .byTools,
                .powerOff: .run { KeyRepeatTool.putBack() },
                .uninstall: .called("KeyRepeatTool.uninstall()"),
            ]),
            Row(owner: "Pointer", changes: "IOHID pointer acceleration per mouse", cells: [
                .start: .byTools,
                .handOver: .byTools,
                .quit: .byTools,
                .powerOff: .none("quit puts it back right after through ToolRegistry"),
                .uninstall: .called("PointerTool.uninstall()"),
            ]),
            Row(owner: "BackgroundTasks", changes: "services and login items turned off on the Background page (launchctl disable through the helper)", cells: [
                .start: .none("the user's choice, kept until they turn it back on"),
                .handOver: .none("the user's choice, kept until they turn it back on"),
                .quit: .none("the user's choice, kept until they turn it back on"),
                .powerOff: .none("the user's choice, kept until they turn it back on"),
                .uninstall: .called("BackgroundTasks.putBack()"),
            ]),
        ]
        #endif
        rows += [
            Row(owner: "LoginItem", changes: nil, cells: [
                .uninstall: .called("LoginItem.shared.apply(false)"),
            ]),
        ]
        #if !APPSTORE
        rows += [
            Row(owner: "Journals", changes: nil, cells: [
                .powerOff: .run { _ = UserDefaults.standard.synchronize() },
            ]),
            Row(owner: "Dock", changes: nil, cells: [
                .powerOff: .restartDock,
            ]),
            Row(owner: "MainDisplay", changes: "display arrangement through CGConfigureDisplayOrigin", cells: [
                .start: .byTools,
                .handOver: .byTools,
                .quit: .byTools,
                .powerOff: .run { MainDisplayControl.restore() },
                .uninstall: .none("DockDisplayTool.uninstall() puts it back"),
            ]),
            Row(owner: "HiddenFiles", changes: "com.apple.finder AppleShowAllFiles", cells: [
                .start: .none("stays on after a crash until the next stop puts it back, SYS-13"),
                .handOver: .run { HiddenFilesTool.putBack() },
                .quit: .run { HiddenFilesTool.putBack() },
                .powerOff: .run { HiddenFilesTool.putBack() },
                .uninstall: .called("HiddenFilesTool.putBack()"),
            ]),
            Row(owner: "TextFocus wait", changes: nil, cells: [
                .quit: .run { _ = TextFocus.puttingBack.wait(timeout: .now() + 2) },
            ]),
        ]
        #endif
        return rows
    }()

    @MainActor static func run(_ moment: Moment, rows: [Row]? = nil, restart: () -> Void = {
        #if !APPSTORE
        AnimationsTool.killall("Dock")
        #endif
    }, log: (String) -> Void = Log.note) {
        #if !APPSTORE
        var asked = false
        let dock = DockHost.offline { asked = true }
        #endif
        for row in rows ?? Self.rows {
            switch row.cells[moment] {
            case .run(let step)?:
                log("\(moment.rawValue) \(row.owner)")
                step()
            #if !APPSTORE
            case .dock(let step)?:
                log("\(moment.rawValue) \(row.owner)")
                if step(dock) { asked = true }
            case .restartDock?:
                guard asked else { continue }
                log("\(moment.rawValue) Dock restart")
                restart()
            #endif
            default:
                continue
            }
        }
    }

    static func stamp(path: String, info: [String: Any]?, system: String) -> String {
        [path, info?["CFBundleShortVersionString"] as? String ?? "", info?["CFBundleVersion"] as? String ?? "", system].joined(separator: "|")
    }

    static func isDue(_ stamp: String, saved: String?, bundleID: String?) -> Bool {
        bundleID == AppConstants.devBundleID || stamp != saved
    }
}
