import AppKit
import ApplicationServices

enum TextFocus {
    case none, unknown, typing(AXUIElement), other(AXUIElement)

    #if !APPSTORE
    private static let lock = NSLock()
    private static var owners: Set<ObjectIdentifier> = []
    private static var observers: [NSObjectProtocol] = []
    private static var awake = Awake()
    private static var plain: Set<pid_t> = []
    private static var retrying: Set<pid_t> = []
    private static var enabled: [Switched] = [] { didSet { Switched.save(stale + enabled, journalKey) } }
    private static var stale: [Switched] = [] { didSet { Switched.save(stale + enabled, journalKey) } }
    private static let running: (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    static let puttingBack = DispatchGroup()
    static let switching = DispatchGroup()
    static let journalKey = PreferenceKey.chromiumAXJournal
    static var write: (String, Bool, pid_t) -> AXError = { attribute, on, pid in
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return AXUIElementSetAttributeValue(app, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    struct Switched: Codable, Equatable {
        let bundleID: String
        let pid: pid_t
        let attribute: String
        let before: Bool

        static func putBack(_ entries: [Switched], bundleID: (pid_t) -> String?) -> [Switched] {
            entries.filter { bundleID($0.pid) == $0.bundleID }
        }

        static func load(_ key: String) -> [Switched] {
            UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Switched].self, from: $0) } ?? []
        }

        static func save(_ entries: [Switched], _ key: String) {
            UserDefaults.standard.set(entries.isEmpty ? nil : try? JSONEncoder().encode(entries), forKey: key)
        }
    }

    struct Awake {
        static let idle: TimeInterval = 60
        private(set) var on: Set<pid_t> = []
        private(set) var away: [pid_t: TimeInterval] = [:]

        mutating func key(_ pid: pid_t) -> Bool {
            away[pid] = nil
            return on.insert(pid).inserted
        }

        mutating func activated(_ pid: pid_t, at now: TimeInterval) -> Bool {
            away[pid] = nil
            let gone = on.filter { $0 != pid && away[$0] == nil }
            for other in gone { away[other] = now }
            return !gone.isEmpty
        }

        mutating func quit(_ pid: pid_t) {
            on.remove(pid)
            away[pid] = nil
        }

        mutating func due(at now: TimeInterval) -> [pid_t] {
            let due = away.filter { now - $0.value >= Self.idle }.keys.sorted()
            for pid in due { quit(pid) }
            return due
        }
    }

    static func putBackAfterCrash(bundleID: @escaping (pid_t) -> String? = running) {
        lock.lock()
        stale = Switched.putBack(Switched.load(journalKey), bundleID: bundleID)
        let todo = stale
        lock.unlock()
        writeBack(todo, bundleID)
    }

    private static func writeBack(_ todo: [Switched], _ bundleID: @escaping (pid_t) -> String?) {
        guard !todo.isEmpty else { return }
        puttingBack.enter()
        DispatchQueue.global(qos: .utility).async {
            for entry in todo {
                for _ in 0..<10 {
                    guard bundleID(entry.pid) == entry.bundleID, write(entry.attribute, entry.before, entry.pid) == .cannotComplete else { break }
                    Thread.sleep(forTimeInterval: 1)
                }
                lock.lock()
                stale.removeAll { $0 == entry }
                lock.unlock()
            }
            puttingBack.leave()
        }
    }

    private static func take(_ gone: (Switched) -> Bool, _ bundleID: (pid_t) -> String?) -> [Switched] {
        guard enabled.contains(where: gone) else { return [] }
        let todo = Switched.putBack(enabled.filter(gone), bundleID: bundleID)
        stale += todo
        enabled.removeAll(where: gone)
        return todo
    }

    static func watch(_ owner: AnyObject, front _: pid_t? = nil) {
        lock.lock()
        owners.insert(ObjectIdentifier(owner))
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers = [
                center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { if let pid = Self.pid($0) { activated(pid) } },
                center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { if let pid = Self.pid($0) { quit(pid) } },
            ]
        }
        lock.unlock()
    }

    static func unwatch(_ owner: AnyObject? = nil, bundleID: @escaping (pid_t) -> String? = running) {
        lock.lock()
        if let owner { owners.remove(ObjectIdentifier(owner)) } else { owners.removeAll() }
        guard owners.isEmpty, !observers.isEmpty else { return lock.unlock() }
        let tokens = observers
        observers = []
        awake = Awake()
        plain = []
        let todo = take({ _ in true }, bundleID)
        lock.unlock()
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        writeBack(todo, bundleID)
    }

    static func activated(_ pid: pid_t, at now: TimeInterval = uptime()) {
        lock.lock()
        let gone = awake.activated(pid, at: now)
        lock.unlock()
        if gone { DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Awake.idle) { putBackIdle() } }
    }

    static func putBackIdle(at now: TimeInterval = uptime(), bundleID: @escaping (pid_t) -> String? = running) {
        lock.lock()
        let due = awake.due(at: now)
        let todo = take({ due.contains($0.pid) }, bundleID)
        lock.unlock()
        writeBack(todo, bundleID)
    }

    static func quit(_ pid: pid_t) {
        lock.lock()
        awake.quit(pid)
        plain.remove(pid)
        if enabled.contains(where: { $0.pid == pid }) { enabled.removeAll { $0.pid == pid } }
        lock.unlock()
    }

    private static func uptime() -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func pid(_ note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    static func wake(_ pid: pid_t) -> Bool {
        lock.lock()
        let known = awake.on.contains(pid)
        if known { _ = awake.key(pid) }
        let skip = known || observers.isEmpty || plain.contains(pid)
        lock.unlock()
        guard !skip else { return false }
        let bundleID = chromium(pid)
        lock.lock()
        let watching = !observers.isEmpty
        if watching && bundleID == nil { plain.insert(pid) }
        let fresh = watching && bundleID != nil && !retrying.contains(pid) && awake.key(pid)
        if fresh { retrying.insert(pid) }
        lock.unlock()
        guard fresh, let bundleID else { return false }
        switching.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                lock.lock()
                retrying.remove(pid)
                lock.unlock()
                switching.leave()
            }
            for _ in 0..<10 {
                var error = turnOn("AXManualAccessibility", pid, bundleID)
                if error != .success { error = turnOn("AXEnhancedUserInterface", pid, bundleID) }
                if error != .cannotComplete { return }
                Thread.sleep(forTimeInterval: 1)
            }
            lock.lock()
            awake.quit(pid)
            let todo = take({ $0.pid == pid }, running)
            lock.unlock()
            writeBack(todo, running)
        }
        return true
    }

    static func enable(_ attribute: String, _ pid: pid_t, _ bundleID: String) -> AXError {
        lock.lock()
        if !observers.isEmpty && !retrying.contains(pid) { _ = awake.key(pid) }
        lock.unlock()
        return turnOn(attribute, pid, bundleID)
    }

    private static func turnOn(_ attribute: String, _ pid: pid_t, _ bundleID: String) -> AXError {
        puttingBack.wait()
        guard let on = isOn(pid) else { return .cannotComplete }
        if on { return .success }
        let entry = Switched(bundleID: bundleID, pid: pid, attribute: attribute, before: false)
        lock.lock()
        let wanted = awake.on.contains(pid)
        if wanted && !enabled.contains(entry) { enabled.append(entry) }
        lock.unlock()
        guard wanted else { return .success }
        var error = write(attribute, true, pid)
        if error == .notImplemented { error = .success }
        let landing = error == .success || error == .cannotComplete
        lock.lock()
        if !landing { enabled.removeAll { $0 == entry } }
        let dropped = landing && !enabled.contains(entry)
        lock.unlock()
        if dropped { _ = write(attribute, false, pid) }
        return error
    }

    static var isOn: (pid_t) -> Bool? = { pid in
        let app = AXUIElementCreateApplication(pid)
        let reads = ["AXManualAccessibility", "AXEnhancedUserInterface", kAXFocusedUIElementAttribute].map { value(app, $0) }
        if reads.prefix(2).contains(where: { $0.0 as? Bool == true }) { return true }
        if reads.contains(where: { $0.1 == .cannotComplete }) { return nil }
        var element = reads[2].0
        for _ in 0..<64 {
            guard let current = element, CFGetTypeID(current) == AXUIElementGetTypeID(), !CFEqual(current, app) else { return false }
            let axCurrent = unsafeBitCast(current, to: AXUIElement.self)
            let role = value(axCurrent, kAXRoleAttribute).0 as? String
            if role == "AXWebArea" { return true }
            if role == nil || role == kAXWindowRole { return false }
            element = value(axCurrent, kAXParentAttribute).0
        }
        return false
    }

    static var chromium: (pid_t) -> String? = { pid in
        guard let app = NSRunningApplication(processIdentifier: pid),
              let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks").path,
              ((try? FileManager.default.contentsOfDirectory(atPath: frameworks)) ?? []).contains(where: { $0.hasSuffix(" Framework.framework") })
        else { return nil }
        return app.bundleIdentifier
    }
    #endif

    init(_ pid: pid_t) {
        #if APPSTORE
        self = Self.read(pid)
        #else
        let deadline = DispatchTime.now() + 0.4
        let fresh = Self.wake(pid)
        self = Self.read(pid)
        guard fresh else { return }
        for _ in 0..<6 {
            if case .typing = self { return }
            guard DispatchTime.now() < deadline else { return }
            Thread.sleep(forTimeInterval: 0.05)
            self = Self.read(pid)
        }
        #endif
    }

    private static func read(_ pid: pid_t) -> TextFocus {
        let (focused, error) = value(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
        if error == .noValue { return .none }
        guard error == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = unsafeBitCast(focused, to: AXUIElement.self)

        let (role, roleError) = value(element, kAXRoleAttribute)
        guard roleError == .success, let role = role as? String else { return .unknown }
        let subrole = value(element, kAXSubroleAttribute).0 as? String
        let typing = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || subrole == kAXSearchFieldSubrole
        return typing ? .typing(element) : .other(element)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> (CFTypeRef?, AXError) {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value, error)
    }
}
