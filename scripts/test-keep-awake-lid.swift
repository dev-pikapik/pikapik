import AppKit

@main
struct TestKeepAwakeLid {
    static func spin(_ seconds: Double) {
        RunLoop.main.run(until: .now + seconds)
    }

    static func waitFor(_ seconds: Double, _ check: () -> Bool) -> Double? {
        let start = Date.now
        while !check() {
            if Date.now.timeIntervalSince(start) > seconds { return nil }
            spin(0.05)
        }
        return Date.now.timeIntervalSince(start)
    }

    static func main() {
        let files = FileManager.default
        let dir = files.temporaryDirectory.appendingPathComponent("pikapik-test-lid-\(UUID().uuidString)")
        try! files.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: dir) }
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let marker = "keep-awake-lid-sleep-disabled"
        let flag = dir.appendingPathComponent("flag")

        var disabled = false
        var answers: [Bool] = []
        var asked: [String] = []
        KeepAwake.lidFlag = flag
        KeepAwake.sleepDisabled = { disabled }
        KeepAwake.askAdmin = { command, _ in
            asked.append(command)
            return answers.isEmpty ? false : answers.removeFirst()
        }
        let center = NotificationCenter()
        KeepAwake.notificationCenter = center
        let keep = KeepAwake.shared

        disabled = true
        files.createFile(atPath: flag.path, contents: Data("1".utf8))
        keep.setLid(true)
        precondition(asked.isEmpty && keep.lidActive && defaults.bool(forKey: marker), "fresh heartbeat is adopted")
        precondition((try? String(contentsOf: flag, encoding: .utf8)) == String(getpid()))

        keep.load()
        precondition(keep.lidActive, "a sync load of the same values called update()")

        center.post(name: NSWorkspace.willPowerOffNotification, object: nil)
        precondition(!files.fileExists(atPath: flag.path) && !keep.lidActive && defaults.bool(forKey: marker) && asked.isEmpty, "log out removes the flag and keeps the marker")

        disabled = false
        precondition(keep.restoreLidSleepIfNeeded())
        spin(5.5)
        precondition(asked.isEmpty && !defaults.bool(forKey: marker) && !keep.lidSleepStuck, "the next launch finds sleep back")

        disabled = true
        files.createFile(atPath: flag.path, contents: Data("1".utf8))
        keep.setLid(true)
        precondition(asked.isEmpty && keep.lidActive)

        answers = [false]
        defaults.set(!keep.keepsDisplayOn, forKey: "keep-awake-display")
        keep.load()
        precondition(!keep.lidActive, "a real display change from a sync calls update()")
        spin(5.5)
        precondition(asked == ["/usr/bin/pmset -a disablesleep 0"] && keep.lidSleepStuck && defaults.bool(forKey: marker), "cancelled restore keeps the marker and shows the row")

        answers = [true]
        keep.letLidSleep()
        precondition(asked.count == 2 && !keep.lidSleepStuck && !defaults.bool(forKey: marker), "retry clears the marker")

        keep.keepsDisplayOn = false
        keep.set(.timed)
        let end = keep.endDate
        defaults.set(keep.duration + 60, forKey: "keep-awake-duration")
        keep.load()
        precondition(keep.mode == .timed && keep.endDate == end && keep.duration == 3660, "a sync load restarted the timed session")
        keep.set(.off)

        files.createFile(atPath: flag.path, contents: Data("1".utf8))
        try! files.setAttributes([.modificationDate: Date.now - 60], ofItemAtPath: flag.path)
        answers = [true]
        keep.setLid(true)
        precondition(asked.count == 3 && asked[2] == KeepAwake.lidScript(flag: flag.path) && keep.lidActive && defaults.bool(forKey: marker), "stale flag starts a new watchdog")

        precondition(!SettingsFile.keys.contains("keep-awake-lid"))

        keep.setLid(false)
        let scheduled = Date.now
        precondition(!files.fileExists(atPath: flag.path))

        testScript(in: dir)

        spin(max(0, 5.5 - Date.now.timeIntervalSince(scheduled)))
        precondition(asked.count == 3 && keep.lidSleepStuck && defaults.bool(forKey: marker), "only one automatic prompt per launch")
        print("Keep Awake lid OK")
    }

    static func testScript(in dir: URL) {
        let files = FileManager.default
        var apps: [Process] = []
        var watchdogs: [pid_t] = []
        defer {
            apps.forEach { $0.terminate() }
            watchdogs.forEach { kill($0, SIGKILL) }
        }

        func app(alive: Bool) -> pid_t {
            let sleep = try! Process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
            apps.append(sleep)
            if !alive {
                sleep.terminate()
                sleep.waitUntilExit()
            }
            return sleep.processIdentifier
        }

        func start(_ name: String, alive: Bool) -> (flag: URL, log: URL, pid: pid_t) {
            let folder = dir.appendingPathComponent(name)
            try! files.createDirectory(at: folder, withIntermediateDirectories: true)
            let pmset = folder.appendingPathComponent("pmset")
            try! "#!/bin/sh\necho \"$*\" >> \"${0%/*}/log\"\n".write(to: pmset, atomically: true, encoding: .utf8)
            try! files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pmset.path)
            let flag = folder.appendingPathComponent("flag with 'quote")
            try! String(app(alive: alive)).write(to: flag, atomically: true, encoding: .utf8)
            let shell = Process()
            let pipe = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", KeepAwake.lidScript(flag: flag.path, pmset: pmset.path, grace: 4) + "\necho $!"]
            shell.standardOutput = pipe
            try! shell.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            shell.waitUntilExit()
            let pid = pid_t(output.trimmingCharacters(in: .whitespacesAndNewlines))!
            watchdogs.append(pid)
            return (flag, folder.appendingPathComponent("log"), pid)
        }

        func lines(_ log: URL) -> [String] {
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }

        func restored(_ log: URL) -> Bool {
            lines(log) == ["-a disablesleep 1", "-a disablesleep 0"]
        }

        func modified(_ url: URL) -> Date {
            (try! files.attributesOfItem(atPath: url.path))[.modificationDate] as! Date
        }

        func gone(_ pid: pid_t) -> Bool {
            kill(pid, 0) != 0
        }

        let removed = start("removed", alive: true)
        let orphan = start("orphan", alive: false)
        let term = start("term", alive: true)
        let beat = start("beat", alive: true)

        spin(1)
        try! files.setAttributes([.modificationDate: Date.now - 60], ofItemAtPath: beat.flag.path)
        let pushedBack = Date.now
        try! files.removeItem(at: removed.flag)
        kill(term.pid, SIGTERM)
        let signalled = Date.now

        precondition(waitFor(3) { restored(removed.log) } != nil, "flag removed: \(lines(removed.log))")
        let afterRemoval = Date.now.timeIntervalSince(signalled)
        precondition(waitFor(1) { gone(removed.pid) } != nil && !files.fileExists(atPath: removed.flag.path), "the removed flag came back")

        precondition(waitFor(3) { restored(term.log) && !files.fileExists(atPath: term.flag.path) } != nil, "SIGTERM: \(lines(term.log))")
        let afterTerm = Date.now.timeIntervalSince(signalled)

        precondition(waitFor(3) { modified(beat.flag) > pushedBack } != nil, "the heartbeat didn't touch the flag")

        precondition(waitFor(6) { restored(orphan.log) } != nil && !files.fileExists(atPath: orphan.flag.path), "app gone: \(lines(orphan.log))")
        let orphanLog = try! files.attributesOfItem(atPath: orphan.log.path)
        precondition((orphanLog[.modificationDate] as! Date).timeIntervalSince(orphanLog[.creationDate] as! Date) > 1.5, "restored before the grace ran out")

        try! files.removeItem(at: beat.flag)
        precondition(waitFor(3) { restored(beat.log) } != nil)
        precondition(waitFor(3) { watchdogs.allSatisfy(gone) } != nil, "a watchdog is still running")
        print(String(format: "Watchdog restored within %.1f s of the flag removal and %.1f s of SIGTERM", afterRemoval, afterTerm))
    }
}
