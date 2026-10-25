import Foundation

final class FakeDock {
    var prefs: [String: Any]
    var coreDock: Bool
    var relaunches = 0
    var corners: [[String: Int]] = []
    var journaled: [Bool] = []
    let journal: UserDefaults
    private let suite: String

    init(_ label: String, _ prefs: [String: Any], coreDock: Bool = true) {
        suite = FileManager.default.temporaryDirectory.appendingPathComponent("test-dock-layers-\(label)-\(UUID().uuidString)").path
        journal = UserDefaults(suiteName: suite)!
        self.prefs = prefs
        self.coreDock = coreDock
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }

    var host: DockHost {
        DockHost(journal: journal, read: { self.prefs[$0] }, write: { name, value in
            self.journaled.append(self.journal.dictionary(forKey: "game-mode-dock") != nil)
            self.prefs[name] = value
        }, setCorners: { actions in
            guard !actions.isEmpty else { return true }
            self.corners.append(actions)
            return self.coreDock
        }, relaunch: { self.relaunches += 1 })
    }

    var clean: Bool { ["game-mode-dock", "hot-corners-before", "hot-corners-ours"].allSatisfy { journal.object(forKey: $0) == nil } }

    func number(_ name: String) -> Double? { (prefs[name] as? NSNumber)?.doubleValue }

    func layered(_ name: String) -> Double? { (DockEdges.read(name, host) as? NSNumber)?.doubleValue }

    func animation(_ setting: AnimationSetting) -> Double? { DockEdges.read(setting.key, host).flatMap(setting.value(from:)) }

    func animate(_ setting: AnimationSetting, _ value: Double?) { DockEdges.write(setting.key, value.map(setting.plist), host) }
}

@main
struct TestDockLayers {
    static let tl = HotCorners.key("tl"), br = HotCorners.key("br"), delay = AnimationSetting.dockDelay.key

    static func main() {
        for restoreFirst in [true, false] {
            let dock = FakeDock("corners-\(restoreFirst)", [br: 2])
            HotCorners.choose(11, side: "br", dock.host)
            DockEdges.calm(corners: [3], hidesDock: false, dock.host)
            precondition(dock.number(br) == 1 && dock.layered(br) == 11, "the game holds the corner over the user's choice: \(dock.prefs)")
            HotCorners.choose(4, side: "br", dock.host)
            precondition(dock.number(br) == 1 && dock.layered(br) == 4 && dock.corners == [[br: 11], [br: 1]], "a choice during the game waits under it: \(dock.prefs) \(dock.corners)")
            if restoreFirst {
                DockEdges.restore(dock.host)
                precondition(dock.number(br) == 4, "the game puts back the choice made during it: \(dock.prefs)")
                HotCorners.putBackAll(dock.host)
            } else {
                HotCorners.putBackAll(dock.host)
                precondition(dock.number(br) == 1 && dock.layered(br) == 2, "the Games page puts back under the game: \(dock.prefs)")
                DockEdges.restore(dock.host)
            }
            precondition(dock.number(br) == 2 && dock.clean && dock.relaunches == 0, "restore first \(restoreFirst): the user's corner is back: \(dock.prefs) \(dock.relaunches)")
        }
        print("a corner chosen during a game waits under the game's value, and the game and the Games page put back in either order to the user's action without a Dock restart: ok")

        for restoreFirst in [true, false] {
            let dock = FakeDock("delay-\(restoreFirst)", ["autohide": true])
            dock.animate(.dockDelay, 0)
            DockEdges.calm(corners: [], hidesDock: true, dock.host)
            precondition(dock.number(delay) == 1000 && dock.animation(.dockDelay) == 0 && dock.relaunches == 1, "the game holds the delay over the Animations value: \(dock.prefs)")
            if restoreFirst {
                DockEdges.restore(dock.host)
                precondition(dock.number(delay) == 0 && dock.relaunches == 2, "the game puts back the Animations value: \(dock.prefs)")
                dock.animate(.dockDelay, nil)
            } else {
                dock.animate(.dockDelay, nil)
                precondition(dock.number(delay) == 1000 && dock.animation(.dockDelay) == nil, "the Animations page puts back under the game: \(dock.prefs)")
                DockEdges.restore(dock.host)
            }
            precondition(dock.prefs[delay] == nil && dock.clean && dock.relaunches == 2, "restore first \(restoreFirst): the delay is missing again: \(dock.prefs) \(dock.relaunches)")
        }
        print("the Dock delay from the Animations page and the game's delay put back in either order, and a delay that was missing stays missing: ok")

        let held = FakeDock("delay-held", ["autohide": true, delay: 0.5])
        DockEdges.calm(corners: [], hidesDock: true, held.host)
        precondition(held.animation(.dockDelay) == 0.5, "during a game the Animations page reads the user's delay, not the game's: \(held.prefs)")
        held.animate(.dockDelay, 0.2)
        precondition(held.number(delay) == 1000 && held.animation(.dockDelay) == 0.2, "a delay set during a game waits under it: \(held.prefs)")
        held.animate(.dockDelay, 0.5)
        DockEdges.restore(held.host)
        precondition(held.number(delay) == 0.5 && held.clean, "the user's delay is back: \(held.prefs)")
        print("during a game the Animations page sees and changes the user's delay, never the game's: ok")

        let hand = FakeDock("by-hand", [tl: 5])
        DockEdges.calm(corners: [0], hidesDock: false, hand.host)
        precondition(hand.number(tl) == 1, "the game holds the corner: \(hand.prefs)")
        hand.prefs[tl] = 7
        precondition(hand.layered(tl) == 7, "a corner changed by hand reads as it is: \(hand.prefs)")
        DockEdges.restore(hand.host)
        precondition(hand.number(tl) == 7 && hand.clean && hand.relaunches == 0, "a corner changed by hand stays: \(hand.prefs)")
        print("a corner the user changes by hand during a game stays as the user set it: ok")

        let crash = FakeDock("crash", [br: 2, "autohide": true])
        DockEdges.calm(corners: [3], hidesDock: true, crash.host)
        crash.journaled = []
        DockEdges.restore(crash.host)
        precondition(crash.journaled == [true, true] && crash.number(br) == 2 && crash.prefs[delay] == nil && crash.clean, "the journal goes only after the writes: \(crash.journaled) \(crash.prefs)")
        print("the game's journal is cleared only after the user's values are written back: ok")

        let old = FakeDock("no-core-dock", [br: 2], coreDock: false)
        DockEdges.calm(corners: [3], hidesDock: false, old.host)
        precondition(old.number(br) == 1 && old.relaunches == 1, "without the corner call the Dock restarts: \(old.relaunches)")
        DockEdges.restore(old.host)
        precondition(old.number(br) == 2 && old.relaunches == 2 && old.clean, "and restarts again on put back: \(old.relaunches)")
        print("without the Dock's corner call the Dock restarts to show the game's corners and the user's: ok")

        var asked = 0
        let offline = DockHost.offline { asked += 1 }
        precondition(offline.setCorners([:]) && !offline.setCorners([br: 1]), "on shutdown corners are not sent to the Dock")
        offline.relaunch()
        precondition(asked == 1, "on shutdown the Dock restart is only noted")

        let mac = FakeDock("power-off", [br: 2, "autohide": true])
        HotCorners.choose(11, side: "br", mac.host)
        DockEdges.calm(corners: [3], hidesDock: true, mac.host)
        (mac.relaunches, mac.corners) = (0, [])
        var restart = false
        let dock = DockHost(journal: mac.journal, read: mac.host.read, write: mac.host.write, setCorners: { $0.isEmpty }, relaunch: { restart = true })
        DockEdges.restore(dock)
        HotCorners.putBackAll(dock)
        precondition(mac.number(br) == 2 && mac.prefs[delay] == nil && mac.clean, "on shutdown the user's values are back: \(mac.prefs)")
        precondition(restart && mac.relaunches == 0 && mac.corners.isEmpty, "on shutdown nothing talks to the Dock, the restart is only noted: \(mac.relaunches) \(mac.corners)")
        print("on shutdown the game's and the Games page's values go back without talking to the Dock, which restarts once at the end: ok")

        let app = try! String(contentsOfFile: "Sources/pikapik/App.swift", encoding: .utf8)
        let handler = app.components(separatedBy: "[SIGTERM, SIGINT, SIGHUP]")[1].components(separatedBy: "source.resume()")[0]
        let putBack = handler.range(of: "if MainCopy.canAct { powerOff() }"), quit = handler.range(of: "Background.quit()")
        precondition(putBack != nil && quit != nil && putBack!.lowerBound < quit!.lowerBound, "a quit signal puts everything back before pikapik quits")
        print("a quit signal from shutdown or kill makes the main copy put everything back before it quits: ok")
    }
}
