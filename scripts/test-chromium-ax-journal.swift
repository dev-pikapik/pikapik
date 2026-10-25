import Foundation

@main
struct TestChromiumAXJournal {
    typealias Switched = TextFocus.Switched

    static let crashKey = "test-chromium-ax-crash"

    static func entry(_ pid: pid_t, _ id: String = "com.google.Chrome", _ attribute: String = "AXManualAccessibility") -> Switched {
        Switched(bundleID: id, pid: pid, attribute: attribute, before: false)
    }

    static func main() {
        let crash = CommandLine.arguments.dropFirst().first == "crash"
        let folder = crash ? URL(fileURLWithPath: CommandLine.arguments[2]) : FileManager.default.temporaryDirectory.appendingPathComponent("test-chromium-ax-journal-\(UUID().uuidString)")
        let suite = folder.appendingPathComponent("journal").path
        let journal = UserDefaults(suiteName: suite)!
        let standard: @convention(block) (AnyObject) -> UserDefaults = { _ in journal }
        method_setImplementation(class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))!, imp_implementationWithBlock(standard))
        precondition(UserDefaults.standard === journal, "the journal must stay in a temporary folder")
        if crash {
            Switched.save([entry(100), entry(200, "com.tinyspeck.slackmacgap", "AXEnhancedUserInterface")], crashKey)
            _exit(0)
        }

        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = "test-chromium-ax-journal"
        let saved = [entry(100), entry(200, "com.tinyspeck.slackmacgap", "AXEnhancedUserInterface")]
        precondition(Switched.load(key).isEmpty)
        Switched.save(saved, key)
        precondition(Switched.load(key) == saved)
        precondition(Switched.load(key)[1].attribute == "AXEnhancedUserInterface" && Switched.load(key)[1].before == false)
        Switched.save([], key)
        precondition(Switched.load(key).isEmpty && UserDefaults.standard.object(forKey: key) == nil)
        print("the remembered apps survive a restart and can be cleared: ok")

        let running: [pid_t: String] = [100: "com.google.Chrome", 200: "com.tinyspeck.slackmacgap", 300: "com.microsoft.VSCode", 400: "com.apple.Safari"]
        func back(_ entries: [Switched]) -> [pid_t] {
            Switched.putBack(entries, bundleID: { running[$0] }).map(\.pid)
        }
        precondition(back([entry(100), entry(200, "com.tinyspeck.slackmacgap", "AXEnhancedUserInterface"), entry(300, "com.microsoft.VSCode")]) == [100, 200, 300])
        print("an app that still runs is put back, even though Chromium answers off while the switch is on: ok")

        precondition(back([entry(999)]).isEmpty)
        precondition(back([entry(100), entry(999), entry(300, "com.microsoft.VSCode")]) == [100, 300])
        print("an app that has quit is dropped: ok")

        precondition(back([entry(400, "com.google.Chrome")]).isEmpty)
        precondition(back([entry(100, "com.google.Chrome.beta")]).isEmpty)
        print("a different app on the same process number is left alone: ok")

        let crashed = Process()
        crashed.executableURL = Bundle.main.executableURL
        crashed.arguments = ["crash", folder.path]
        try! crashed.run()
        crashed.waitUntilExit()
        CFPreferencesAppSynchronize(suite as CFString)
        precondition(Switched.load(crashKey) == saved)
        print("after a crash the next launch finds what was switched on: ok")

        var writes: [String] = []
        TextFocus.write = { _, on, pid in
            if !on { Thread.sleep(forTimeInterval: 0.3) }
            writes.append("\(pid) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
            return .success
        }
        let gone = crashed.processIdentifier
        let chrome: (pid_t) -> String? = { $0 == 100 || $0 == gone ? "com.google.Chrome" : nil }
        Switched.save([entry(100)], TextFocus.journalKey)
        TextFocus.putBackAfterCrash(bundleID: chrome)
        precondition(writes.isEmpty, "putBackAfterCrash must return before it writes")
        TextFocus.isOn = { _ in false }
        let owner = NSObject()
        TextFocus.watch(owner)
        precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .success)
        precondition(writes == ["100 false [100]", "\(gone) true [\(gone)]"], "\(writes)")
        print("putting back runs off the main thread, the journal holds an app before its switch changes, and putting back finishes before a new switch: ok")

        TextFocus.unwatch(owner, bundleID: chrome)
        precondition(writes.count == 2, "unwatch must return before it writes")
        TextFocus.puttingBack.wait()
        precondition(writes == ["100 false [100]", "\(gone) true [\(gone)]", "\(gone) false [\(gone)]"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        print("switching off runs off the main thread and keeps each app in the journal until it is put back: ok")

        writes = []
        TextFocus.isOn = { $0 == gone }
        TextFocus.watch(owner)
        precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .success)
        precondition(TextFocus.enable("AXEnhancedUserInterface", gone, "com.google.Chrome") == .success)
        precondition(writes.isEmpty && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        TextFocus.unwatch(owner, bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes.isEmpty && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        TextFocus.isOn = { _ in false }
        print("an app that was already on is not switched, not remembered and not switched off: ok")

        writes = []
        TextFocus.write = { attribute, on, _ in
            writes.append("\(attribute) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
            return attribute == "AXManualAccessibility" ? .attributeUnsupported : .notImplemented
        }
        TextFocus.watch(owner)
        precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .attributeUnsupported)
        precondition(TextFocus.enable("AXEnhancedUserInterface", gone, "com.google.Chrome") == .success)
        TextFocus.unwatch(owner, bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes == ["AXManualAccessibility true [\(gone)]", "AXEnhancedUserInterface true [\(gone)]", "AXEnhancedUserInterface false [\(gone)]"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        print("Chrome turns on although it answers that the switch is not implemented, so it is remembered and turned off: ok")

        var timeouts = 1
        writes = []
        TextFocus.write = { _, on, pid in
            writes.append("\(pid) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
            timeouts -= 1
            return timeouts >= 0 ? .cannotComplete : .success
        }
        Switched.save([entry(100)], TextFocus.journalKey)
        TextFocus.putBackAfterCrash(bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes == ["100 false [100]", "100 false [100]"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        print("a put-back that times out is tried again, and the app stays in the journal until then: ok")

        var alive = true
        writes = []
        TextFocus.write = { _, on, pid in
            writes.append("\(pid) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
            alive = false
            return .cannotComplete
        }
        Switched.save([entry(100)], TextFocus.journalKey)
        TextFocus.putBackAfterCrash(bundleID: { $0 == 100 && alive ? "com.google.Chrome" : nil })
        TextFocus.puttingBack.wait()
        precondition(writes == ["100 false [100]"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        print("a put-back stops trying once the app has quit: ok")

        var busy = true
        var mode: [String: Bool] = [:]
        writes = []
        TextFocus.write = { attribute, on, _ in
            writes.append("\(attribute) \(on) \(Switched.load(TextFocus.journalKey).count)")
            mode[attribute] = on
            return busy ? .cannotComplete : .success
        }
        TextFocus.isOn = { _ in !busy && mode.values.contains(true) }
        TextFocus.watch(owner)
        for _ in 0..<2 {
            precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .cannotComplete)
            precondition(TextFocus.enable("AXEnhancedUserInterface", gone, "com.google.Chrome") == .cannotComplete)
        }
        busy = false
        precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .success)
        TextFocus.unwatch(bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(!mode.values.contains(true) && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        precondition(writes == ["AXManualAccessibility true 1", "AXEnhancedUserInterface true 2", "AXManualAccessibility true 2", "AXEnhancedUserInterface true 2", "AXManualAccessibility false 2", "AXEnhancedUserInterface false 1"], "\(writes)")
        print("a busy Chrome that turns on after answering too late is remembered once and turned off at quit: ok")

        busy = true
        mode = ["AXManualAccessibility": true]
        writes = []
        TextFocus.isOn = { _ in busy ? nil : mode.values.contains(true) }
        TextFocus.watch(owner)
        for _ in 0..<10 {
            precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .cannotComplete)
            precondition(TextFocus.enable("AXEnhancedUserInterface", gone, "com.google.Chrome") == .cannotComplete)
        }
        busy = false
        precondition(TextFocus.enable("AXManualAccessibility", gone, "com.google.Chrome") == .success)
        TextFocus.unwatch(bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(mode == ["AXManualAccessibility": true] && writes.isEmpty && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        print("a Chrome that another program turned on and that does not answer is neither switched nor remembered, and stays on at quit: ok")

        var idle = TextFocus.Awake()
        precondition(!idle.activated(1, at: 0) && idle.due(at: 1000).isEmpty)
        var awake = TextFocus.Awake()
        precondition(awake.key(1) && !awake.key(1))
        precondition(awake.activated(2, at: 0))
        precondition(awake.due(at: 59).isEmpty && awake.due(at: 60) == [1] && awake.on.isEmpty)
        _ = awake.key(1)
        precondition(awake.activated(2, at: 0))
        precondition(!awake.activated(1, at: 30) && awake.due(at: 60).isEmpty)
        precondition(awake.activated(2, at: 40) && awake.due(at: 99).isEmpty && awake.due(at: 100) == [1])
        _ = awake.key(1)
        _ = awake.activated(2, at: 0)
        awake.quit(1)
        precondition(awake.due(at: 1000).isEmpty && awake.on.isEmpty)
        for pid: pid_t in [3, 1, 2] { _ = awake.key(pid) }
        precondition(awake.activated(9, at: 0) && awake.due(at: 60) == [1, 2, 3])
        _ = awake.key(1)
        _ = awake.activated(2, at: 0)
        _ = awake.key(1)
        precondition(awake.due(at: 60).isEmpty && awake.on == [1])
        print("an app is put back after a minute in the background, coming back or a key keeps it on, and an app that quits is forgotten: ok")

        let apps: [pid_t: String] = [7: "com.google.Chrome", 8: "com.tinyspeck.slackmacgap"]
        var checked: [pid_t] = []
        writes = []
        TextFocus.write = { _, on, pid in
            writes.append("\(pid) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
            return .success
        }
        TextFocus.isOn = { _ in false }
        TextFocus.chromium = { checked.append($0); return apps[$0] }
        TextFocus.watch(owner)
        precondition(TextFocus.wake(7))
        TextFocus.switching.wait()
        precondition(writes == ["7 true [7]"], "\(writes)")
        precondition(!TextFocus.wake(7) && !TextFocus.wake(9) && !TextFocus.wake(9) && checked == [7, 9], "\(checked)")
        TextFocus.activated(9, at: 0)
        TextFocus.putBackIdle(at: 59, bundleID: { apps[$0] })
        TextFocus.puttingBack.wait()
        precondition(writes == ["7 true [7]"], "\(writes)")
        TextFocus.putBackIdle(at: 60, bundleID: { apps[$0] })
        TextFocus.puttingBack.wait()
        precondition(writes == ["7 true [7]", "7 false [7]"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        precondition(TextFocus.wake(7))
        TextFocus.switching.wait()
        precondition(TextFocus.wake(8))
        TextFocus.switching.wait()
        precondition(writes == ["7 true [7]", "7 false [7]", "7 true [7]", "8 true [7, 8]"], "\(writes)")
        TextFocus.quit(7)
        precondition(Switched.load(TextFocus.journalKey).map(\.pid) == [8] && writes.count == 4, "\(writes)")
        TextFocus.unwatch(owner, bundleID: { apps[$0] })
        TextFocus.puttingBack.wait()
        precondition(writes.last == "8 false [8]" && writes.count == 5 && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
        precondition(!TextFocus.wake(7) && checked == [7, 9, 7, 8], "\(checked)")
        print("an app is switched on at the first key and checked for Chromium once, put back after a minute in the background, switched on again at the next key, and dropped from the journal when it quits: ok")

        for background in [false, true] {
            writes = []
            let sent = DispatchSemaphore(value: 0), landed = DispatchSemaphore(value: 0)
            let chrome7: (pid_t) -> String? = { $0 == 7 ? "com.google.Chrome" : nil }
            TextFocus.chromium = chrome7
            TextFocus.write = { attribute, on, pid in
                if on && attribute == "AXEnhancedUserInterface" { sent.signal(); landed.wait() }
                writes.append("\(pid) \(on) \(Switched.load(TextFocus.journalKey).map(\.pid))")
                return on ? .cannotComplete : .success
            }
            TextFocus.watch(owner)
            precondition(TextFocus.wake(7))
            sent.wait()
            if background {
                TextFocus.activated(9, at: 0)
                TextFocus.putBackIdle(at: 60, bundleID: chrome7)
                TextFocus.puttingBack.wait()
            } else {
                TextFocus.quit(7)
            }
            precondition(Switched.load(TextFocus.journalKey).isEmpty)
            precondition(TextFocus.enable("AXManualAccessibility", 7, "com.google.Chrome") == .success && !TextFocus.wake(7))
            landed.signal()
            TextFocus.switching.wait()
            TextFocus.puttingBack.wait()
            let off = background ? ["7 false [7, 7]", "7 false [7]"] : []
            precondition(writes == ["7 true [7]"] + off + ["7 true []", "7 false []"] && Switched.load(TextFocus.journalKey).isEmpty, "\(writes)")
            TextFocus.unwatch(owner)
            TextFocus.puttingBack.wait()
        }
        print("an app that quits or stays in the background while it is still being switched on ends switched off and out of the journal, and nothing switches it back on: ok")
    }
}
