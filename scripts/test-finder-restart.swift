import AppKit

final class FakeFinder {
    var pid: pid_t? = 400
    var cpu = 3.0
    var io: UInt64 = 1_000_000
    var signals: [pid_t] = []
    var waits: [() -> Void] = []

    var host: FinderHost {
        FinderHost(
            pid: { self.pid },
            activity: { $0 == self.pid ? (self.cpu, self.io) : nil },
            terminate: { self.signals.append($0) },
            later: { self.waits.append($0) }
        )
    }

    func wait(copying: Bool) {
        if copying { io += 1 << 20 }
        waits.removeFirst()()
    }
}

@main
struct TestFinderRestart {
    static func main() {
        let me = getpid()
        let start = FinderHost.system.activity(me)!
        usleep(500_000)
        let rested = FinderHost.system.activity(me)!
        let work = clock()
        while clock() - work < CLOCKS_PER_SEC / 20 {}
        let worked = FinderHost.system.activity(me)!
        precondition(!HiddenFilesTool.busy(start, rested), "a process that sleeps is not busy: \(start) \(rested)")
        precondition(worked.cpu - rested.cpu > 0.04 && worked.cpu - rested.cpu < 1 && HiddenFilesTool.busy(rested, worked), "50 ms of work reads as 50 ms and as busy: \(worked.cpu - rested.cpu)")
        print("Finder's work is measured in seconds: ok")

        precondition(!HiddenFilesTool.busy((0, 7), (0.005, 7)) && !HiddenFilesTool.busy((120, 7), (120.004, 7)) && !HiddenFilesTool.busy((2, 7), (2, 7)), "up to 5 ms of work in half a second is idle")
        precondition(HiddenFilesTool.busy((0, 7), (0.006, 7)) && HiddenFilesTool.busy((120, 7), (120.5, 7)), "more than 5 ms of work is busy")
        precondition(HiddenFilesTool.busy((2, 7), (2, 8)), "any disk activity is busy")
        print("Finder is busy with more than 5 ms of work or any disk activity in half a second: ok")

        let asked = Date()
        var waited: TimeInterval?
        FinderHost.system.later { waited = Date().timeIntervalSince(asked) }
        while waited == nil { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        precondition(waited! >= 0.5 && waited! < 3, "Finder is measured again after half a second: \(waited!)")
        print("the next look at Finder comes half a second later: ok")

        check("Hide desktop icons") { let tool = DesktopIconsTool(finder: $0); return (tool.restartFinder, { tool.finderBusy }) }
        check("Show hidden files") { let tool = HiddenFilesTool(finder: $0); return (tool.restartFinder, { tool.waitingForFinder }) }
    }

    static func check(_ name: String, _ make: (FinderHost) -> (restart: () -> Void, waiting: () -> Bool)) {
        let finder = FakeFinder()
        let tool = make(finder.host)
        tool.restart()
        precondition(finder.waits.count == 1 && finder.signals.isEmpty && !tool.waiting(), "\(name): Finder is measured first and nothing restarts yet")
        finder.wait(copying: true)
        precondition(tool.waiting() && finder.signals.isEmpty && finder.waits.count == 1, "\(name): while Finder copies, it waits and says so")
        finder.wait(copying: true)
        precondition(tool.waiting() && finder.signals.isEmpty && finder.waits.count == 1, "\(name): it keeps waiting while the copy goes on")
        finder.wait(copying: false)
        precondition(!tool.waiting() && finder.signals == [400] && finder.waits.isEmpty, "\(name): once Finder is free, it restarts Finder exactly once: \(finder.signals)")
        print("\(name) waits while Finder copies, then restarts it once: ok")

        let gone = FakeFinder()
        let left = make(gone.host)
        left.restart()
        gone.wait(copying: true)
        gone.pid = nil
        gone.wait(copying: false)
        precondition(!left.waiting() && gone.signals.isEmpty && gone.waits.isEmpty, "\(name): when Finder goes away, the wait ends")

        let none = FakeFinder()
        none.pid = nil
        let alone = make(none.host)
        alone.restart()
        precondition(!alone.waiting() && none.waits.isEmpty && none.signals.isEmpty, "\(name): without Finder there is nothing to wait for")
        print("\(name) stops waiting when Finder is gone: ok")
    }
}
