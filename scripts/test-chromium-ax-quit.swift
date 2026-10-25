import Foundation

@main
struct TestChromiumAXQuit {
    static func main() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("test-chromium-ax-quit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = UserDefaults(suiteName: folder.appendingPathComponent("journal").path)!
        let standard: @convention(block) (AnyObject) -> UserDefaults = { _ in journal }
        method_setImplementation(class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))!, imp_implementationWithBlock(standard))
        precondition(UserDefaults.standard === journal, "the journal must stay in a temporary folder")

        let pid: pid_t = 100
        let chrome: (pid_t) -> String? = { $0 == pid ? "com.google.Chrome" : nil }
        func remembered() -> [pid_t] { TextFocus.Switched.load(TextFocus.journalKey).map(\.pid) }
        func switchOn() -> Bool { TextFocus.enable("AXManualAccessibility", pid, "com.google.Chrome") == .success }
        var writes: [Bool] = []
        TextFocus.isOn = { _ in false }

        let sent = DispatchSemaphore(value: 0), landed = DispatchSemaphore(value: 0), returned = DispatchSemaphore(value: 0)
        TextFocus.write = { _, on, _ in
            if on { sent.signal(); landed.wait() }
            writes.append(on)
            return .success
        }
        let owner = NSObject()
        TextFocus.watch(owner, front: nil)
        var switched = false
        DispatchQueue.global().async {
            switched = TextFocus.enable("AXManualAccessibility", pid, "com.google.Chrome") == .success
            returned.signal()
        }
        sent.wait()
        precondition(remembered() == [pid])
        TextFocus.unwatch(owner, bundleID: chrome)
        TextFocus.puttingBack.wait()
        landed.signal()
        returned.wait()
        precondition(switched && writes == [false, true, false] && remembered().isEmpty, "\(writes)")
        print("an app whose switch-on lands after pikapik has put it back is switched off again: ok")

        writes = []
        TextFocus.write = { _, on, _ in
            writes.append(on)
            return .success
        }
        precondition(switchOn() && writes.isEmpty && remembered().isEmpty, "\(writes)")
        print("a switch-on tried again after pikapik stopped watching neither switches nor remembers the app: ok")

        let homeEnd = NSObject(), retype = NSObject()
        TextFocus.watch(homeEnd, front: nil)
        TextFocus.watch(retype, front: nil)
        precondition(switchOn())
        TextFocus.unwatch(homeEnd, bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes == [true] && remembered() == [pid], "\(writes)")
        TextFocus.unwatch(retype, bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes == [true, false] && remembered().isEmpty, "\(writes)")
        print("turning off Home/End keeps the app switched on while Retype still needs it, and the last one switches it off: ok")

        writes = []
        TextFocus.watch(homeEnd, front: nil)
        TextFocus.watch(retype, front: nil)
        precondition(switchOn())
        TextFocus.unwatch(bundleID: chrome)
        TextFocus.puttingBack.wait()
        precondition(writes == [true, false] && remembered().isEmpty, "\(writes)")
        print("quitting switches the app off even while both features are on: ok")
    }
}
