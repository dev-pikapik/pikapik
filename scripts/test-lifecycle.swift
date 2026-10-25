import Foundation

final class Trace {
    var steps: [String] = []
    var logs: [String] = []
    var offline: [Bool] = []
}

@main
@MainActor
enum TestLifecycle {
    static func runs(_ cell: Lifecycle.Cell?) -> Bool {
        switch cell {
        case .run?, .dock?, .restartDock?: return true
        default: return false
        }
    }

    static func executed(_ moment: Lifecycle.Moment, _ rows: [Lifecycle.Row]) -> [String] {
        rows.filter { runs($0.cells[moment]) }.map(\.owner)
    }

    static func called(_ moment: Lifecycle.Moment, _ rows: [Lifecycle.Row]) -> [String] {
        rows.compactMap { row in
            guard case .called(let text)? = row.cells[moment] else { return nil }
            return text
        }
    }

    static func isOffline(_ host: DockHost) -> Bool {
        host.journal === UserDefaults.standard && host.setCorners([:]) && !host.setCorners(["wvous-tl-corner": 1])
    }

    static func fake(_ trace: Trace, relaunch: Bool, returns: Bool) -> [Lifecycle.Row] {
        [
            Lifecycle.Row(owner: "one", changes: nil, cells: [.powerOff: .run { trace.steps.append("one") }, .quit: .run { trace.steps.append("one quit") }]),
            Lifecycle.Row(owner: "tools", changes: nil, cells: [.powerOff: .byTools, .quit: .byTools]),
            Lifecycle.Row(owner: "called", changes: nil, cells: [.powerOff: .called("x()"), .quit: .called("x()")]),
            Lifecycle.Row(owner: "none", changes: nil, cells: [.powerOff: .none("y"), .quit: .none("y")]),
            Lifecycle.Row(owner: "relaunch", changes: nil, cells: [.powerOff: .dock { host in
                trace.steps.append("relaunch")
                trace.offline.append(isOffline(host))
                if relaunch { host.relaunch() }
                return false
            }]),
            Lifecycle.Row(owner: "returns", changes: nil, cells: [.powerOff: .dock { host in
                trace.steps.append("returns")
                trace.offline.append(isOffline(host))
                return returns
            }]),
            Lifecycle.Row(owner: "Dock", changes: nil, cells: [.powerOff: .restartDock]),
            Lifecycle.Row(owner: "below", changes: nil, cells: [.powerOff: .run { trace.steps.append("below") }, .quit: .run { trace.steps.append("below quit") }]),
        ]
    }

    static func main() {
        for (relaunch, returns) in [(false, false), (true, false), (false, true), (true, true)] {
            let trace = Trace()
            var restarts = 0
            Lifecycle.run(.powerOff, rows: fake(trace, relaunch: relaunch, returns: returns), restart: {
                restarts += 1
                trace.steps.append("restart")
            }, log: { trace.logs.append($0) })
            let asked = relaunch || returns
            let restart = asked ? ["restart"] : []
            precondition(trace.steps == ["one", "relaunch", "returns"] + restart + ["below"], "rows run top to bottom, cells without code are skipped, the restart comes at the Dock row: \(trace.steps)")
            precondition(restarts == (asked ? 1 : 0), "the Dock restarts once, and only when a cell asked for it: \(restarts) for \(relaunch) \(returns)")
            precondition(trace.logs == ["powerOff one", "powerOff relaunch", "powerOff returns"] + (asked ? ["powerOff Dock restart"] : []) + ["powerOff below"], "every step and the restart are logged: \(trace.logs)")
            precondition(trace.offline == [true, true], "Dock cells get the offline host, which never asks the Dock to set corners: \(trace.offline)")
        }
        let trace = Trace()
        Lifecycle.run(.quit, rows: fake(trace, relaunch: true, returns: true), restart: { trace.steps.append("restart") }, log: { trace.logs.append($0) })
        precondition(trace.steps == ["one quit", "below quit"] && trace.logs == ["quit one", "quit below"], "a moment runs only its own cells: \(trace.steps) \(trace.logs)")
        print("lifecycle runner: ok")

        let rows = Lifecycle.rows
        let expected: [Lifecycle.Moment: [String]] = [
            .start: ["TextFocus", "DesktopIcons", "ToolRegistry", "Permissions", "SettingsSync", "Brightness", "KeepAwake", "Updater"],
            .handOver: ["TextFocus", "DesktopIcons", "ToolRegistry", "SettingsSync", "Brightness", "KeepAwake", "FanControl", "Updater", "GameMode", "DockEdges", "HotCorners", "HiddenFiles"],
            .quit: ["TextFocus", "DesktopIcons", "ToolRegistry", "SettingsSync", "Brightness", "FanControl", "Updater", "GameMode", "DockEdges", "HotCorners", "HiddenFiles", "TextFocus wait"],
            .powerOff: ["DesktopIcons", "DockEdges", "HotCorners", "Animations", "DockDisplay", "KeyRepeat", "Journals", "Dock", "MainDisplay", "HiddenFiles"],
            .uninstall: [],
        ]
        for moment in Lifecycle.Moment.allCases {
            precondition(executed(moment, rows) == expected[moment], "\(moment.rawValue) runs \(executed(moment, rows))")
        }
        precondition(Set(rows.map(\.owner)).count == rows.count, "every owner has one row")
        for row in rows where row.changes != nil {
            let missing = Lifecycle.Moment.allCases.filter { row.cells[$0] == nil }
            precondition(missing.isEmpty, "\(row.owner) changes the Mac, so every moment says what happens to it: \(missing.map(\.rawValue))")
        }
        let barrier = rows.firstIndex { if case .restartDock? = $0.cells[.powerOff] { return true } else { return false } }!
        for (index, row) in rows.enumerated() {
            for (moment, cell) in row.cells {
                if case .dock = cell { precondition(moment == .powerOff && index < barrier, "\(row.owner) uses the offline Dock at \(moment.rawValue), so the restart below it would miss it") }
                if case .restartDock = cell { precondition(moment == .powerOff && index == barrier, "\(row.owner) restarts the Dock at \(moment.rawValue)") }
            }
        }
        let start = executed(.start, rows)
        precondition(["TextFocus", "DesktopIcons"].allSatisfy { start.firstIndex(of: $0)! < start.firstIndex(of: "ToolRegistry")! }, "leftovers of a crash are put back before the tools start, or the put-back undoes what the tools just did: \(start)")
        precondition(executed(.quit, rows).last == "TextFocus wait", "quitting waits for the Chromium put-back after everything else")
        print("lifecycle table: ok")

        let main = try! String(contentsOfFile: "Sources/pikapik/main.swift", encoding: .utf8)
        let block = main.components(separatedBy: "if CommandLine.arguments.contains(\"--uninstall\") {\n")[1].components(separatedBy: "\n}\n")[0]
        let statements = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.contains("Brew.") && $0 != "exit(0)" }
        let uninstall = called(.uninstall, rows)
        precondition(!statements.isEmpty && Set(uninstall).count == uninstall.count, "uninstall: \(statements) \(uninstall)")
        for statement in statements {
            precondition(uninstall.filter { statement.contains($0) }.count == 1, "main.swift --uninstall runs \(statement), which the table does not name")
        }
        for text in uninstall {
            precondition(statements.contains { $0.contains(text) }, "the table says --uninstall calls \(text), main.swift does not")
        }
        print("lifecycle uninstall: ok")

        let app = try! String(contentsOfFile: "Sources/pikapik/App.swift", encoding: .utf8)
        let willTerminate = app.components(separatedBy: "func applicationWillTerminate(")[1].components(separatedBy: "\n    }\n")[0]
        let quit = called(.quit, rows)
        precondition(!quit.isEmpty, "quit names what applicationWillTerminate calls")
        for text in quit {
            precondition(willTerminate.contains(text), "the table says quitting calls \(text), applicationWillTerminate does not")
        }
        print("lifecycle quit: ok")

        let patterns = ["CFPreferencesSet", "IOHIDServiceClientSetProperty", "CGConfigureDisplayOrigin", "CoreDockSet", "CGSSetSymbolicHotKeyEnabled", "CGSetDisplayTransferByTable", "disablesleep", "AXManualAccessibility", #"launchctl(["disable""#]
        let owners: [String: [String]] = [
            "Sources/pikapik/Core/TextFocus.swift": ["TextFocus"],
            "Sources/pikapik/Tools/Animations/AnimationSetting.swift": ["Animations"],
            "Sources/pikapik/Tools/Animations/AnimationsTool.swift": ["Animations"],
            "Sources/pikapik/Tools/Background/BackgroundTasks.swift": ["BackgroundTasks"],
            "Sources/pikapik/Tools/Brightness/Brightness.swift": ["Brightness"],
            "Sources/pikapik/Tools/Dock/DockDisplayTool.swift": ["DockDisplay", "MainDisplay"],
            "Sources/pikapik/Tools/Fans/FanHelperProtocol.swift": ["BackgroundTasks", "FanControl"],
            "Sources/pikapik/Tools/Finder/DesktopIcons.swift": ["DesktopIcons"],
            "Sources/pikapik/Tools/Finder/DesktopTools.swift": ["HiddenFiles"],
            "Sources/pikapik/Tools/Games/DockEdges.swift": ["DockEdges", "HotCorners"],
            "Sources/pikapik/Tools/Games/GameRules.swift": ["GameMode"],
            "Sources/pikapik/Tools/Games/HotCorners.swift": ["HotCorners"],
            "Sources/pikapik/Tools/KeepAwake/KeepAwake.swift": ["KeepAwake"],
            "Sources/pikapik/Tools/KeyRepeat/KeyRepeatTool.swift": ["KeyRepeat"],
            "Sources/pikapik/Tools/Mouse/PointerTool.swift": ["Pointer"],
        ]
        let allowed = ["Sources/pikapik/Core/Lifecycle.swift": "the table itself names them"]
        let files = FileManager.default.enumerator(atPath: "Sources")!.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.map { "Sources/" + $0 }
        let hits = Set(files.filter { file in
            let text = try! String(contentsOfFile: file, encoding: .utf8)
            return patterns.contains { text.contains($0) }
        })
        precondition(hits.count > 10, "the scan finds the files: \(hits)")
        for file in hits.sorted() {
            precondition(owners[file] != nil || allowed[file] != nil, "\(file) changes the Mac but no table row owns it: give the change a row in Lifecycle.swift and add the file here")
        }
        for file in Array(owners.keys) + Array(allowed.keys) {
            precondition(hits.contains(file), "\(file) no longer changes the Mac, drop it from the map")
        }
        for owner in Set(owners.values.joined()).sorted() {
            precondition(rows.contains { $0.owner == owner && $0.changes != nil }, "\(owner) changes the Mac but its row does not say what")
        }
        print("lifecycle scan: ok")

        for moment in Lifecycle.Moment.allCases {
            let finder = rows.filter { $0.restartsFinder.contains(moment) }
            precondition(finder.count <= 1, "\(finder.map(\.owner)) can each restart Finder at \(moment.rawValue), so Finder could restart twice: ask the runner for one restart instead")
            for row in finder {
                precondition(runs(row.cells[moment]) || !called(moment, [row]).isEmpty, "\(row.owner) says it restarts Finder at \(moment.rawValue), where it has no step")
            }
        }
        let finderOwners = ["Sources/pikapik/Tools/Finder/DesktopTools.swift": "HiddenFiles"]
        let finderAllowed = [
            "Sources/pikapik/Tools/Animations/AnimationSetting.swift": "restartFinder() runs only from FinderRestart: the check after launch and the Restart Finder buttons",
            "Sources/pikapik/Tools/Windows/QuitOnCloseTool.swift": "it never quits Finder, com.apple.finder is always excluded",
        ]
        let finderKills = Set(files.filter { file in
            let text = try! String(contentsOfFile: file, encoding: .utf8)
            let named = text.range(of: #"kill(all)?\("Finder"|killall Finder|"Finder"\]"#, options: .regularExpression) != nil
            let mentions = text.contains("finderBundleID") || text.contains(#""com.apple.finder""#)
            return named || mentions && text.range(of: #"(?<![.\w])kill\(|\.(force)?[tT]erminate\(\)"#, options: .regularExpression) != nil
        })
        for file in finderKills.sorted() {
            precondition(finderOwners[file] != nil || finderAllowed[file] != nil, "\(file) can kill Finder but no table row says when: declare restartsFinder on its row in Lifecycle.swift and add the file here")
        }
        for file in Array(finderOwners.keys) + Array(finderAllowed.keys) {
            precondition(finderKills.contains(file), "\(file) no longer kills Finder, drop it from the map")
        }
        for owner in Set(finderOwners.values).sorted() {
            precondition(rows.contains { $0.owner == owner && !$0.restartsFinder.isEmpty }, "\(owner) kills Finder but its row does not say at which moments")
        }
        print("lifecycle finder: ok")

        let info: [String: Any] = ["CFBundleShortVersionString": "1.53.1", "CFBundleVersion": "1531"]
        let system = "Version 27.0 (Build 27A1)"
        let stamp = Lifecycle.stamp(path: "/Applications/pikapik.app", info: info, system: system)
        precondition(stamp == "/Applications/pikapik.app|1.53.1|1531|Version 27.0 (Build 27A1)", "the stamp names the place, the version, the build and macOS: \(stamp)")
        let website = AppConstants.directBundleID
        precondition(Lifecycle.isDue(stamp, saved: nil, bundleID: website), "the first launch registers everything")
        precondition(!Lifecycle.isDue(stamp, saved: stamp, bundleID: website), "the same copy at the same place skips the registrations")
        precondition(!Lifecycle.isDue(stamp, saved: stamp, bundleID: AppConstants.appStoreBundleID), "the App Store copy at the same place skips the registrations too")
        for changed in [
            Lifecycle.stamp(path: "/Users/me/Applications/pikapik.app", info: info, system: system),
            Lifecycle.stamp(path: "/Applications/pikapik.app", info: ["CFBundleShortVersionString": "1.54.0", "CFBundleVersion": "1540"], system: system),
            Lifecycle.stamp(path: "/Applications/pikapik.app", info: ["CFBundleShortVersionString": "1.53.1", "CFBundleVersion": "1532"], system: system),
            Lifecycle.stamp(path: "/Applications/pikapik.app", info: info, system: "Version 27.1 (Build 27B1)"),
        ] {
            precondition(Lifecycle.isDue(changed, saved: stamp, bundleID: website), "a move, an update, a new build or a new macOS registers again: \(changed)")
        }
        precondition(Lifecycle.isDue(stamp, saved: stamp, bundleID: AppConstants.devBundleID), "the dev build registers at every launch")
        precondition(!SettingsFile.keys.contains(PreferenceKey.launchMaintenance), "the stamp belongs to this Mac, so settings sync must not carry it to another")
        print("lifecycle maintenance: ok")
    }
}
