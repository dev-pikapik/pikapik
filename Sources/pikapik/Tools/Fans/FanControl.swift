import SwiftUI

@Observable
final class FanControl {
    static let shared = FanControl()
    private static let rpmKey = PreferenceKey.fansRPM
    private static let app = Bundle.main.bundleIdentifier ?? FanHelperInfo.appIdentifier
    private static let label = app + FanHelperInfo.suffix
    private static let helperDir = "/Library/PrivilegedHelperTools"
    private static let binary = helperDir + "/" + label
    private static let plist = "/Library/LaunchDaemons/" + label + ".plist"
    private static let record = binary + FanHelperInfo.recordSuffix
    private static let oldServicesKey = PreferenceKey.backgroundTurnedOffServices
    private static let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/fan-helper")
    private static let launchctlPath = SystemPath.launchctl
    private static let mkdirPath = SystemPath.mkdir
    private static let rmPath = SystemPath.rm
    private static let cpPath = SystemPath.cp
    private static let chownPath = SystemPath.chown
    private static let chmodPath = SystemPath.chmod
    private static let codesignPath = SystemPath.codesign
    private static let printfPath = SystemPath.printf
    private static let sleepPath = SystemPath.sleep

    @ObservationIgnored private let smc = SMC()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var requested: [Int: Date] = [:]
    @ObservationIgnored private var updated = false

    private(set) var fans: [SMCFan] = []
    private(set) var wanted: [Int: Double] = [:]
    private(set) var ready = false
    private(set) var busy = false
    private(set) var error: String?

    init() {
        fans = smc?.fans() ?? []
    }

    var hasFans: Bool { !fans.isEmpty }

    static var turnedOffServices: [String] { ServiceSwitch.turnedOff(record) }

    var summary: Text {
        guard let first = fans.first else { return Text(verbatim: "") }
        return wanted.isEmpty ? Text("Auto · \(Int(first.current)) rpm") : Text("Manual · \(Int(first.current)) rpm")
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [self] _ in
            wanted.keys.forEach(setAuto)
        }
    }

    func watch() {
        watchers += 1
        guard timer == nil else { return }
        refresh()
        probe()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in refresh() }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func savedRPM(_ fan: SMCFan) -> Double {
        let saved = (UserDefaults.standard.stringArray(forKey: Self.rpmKey) ?? [])
            .compactMap { $0.split(separator: ":").map(String.init) }
            .first { $0.first == String(fan.id) }
            .flatMap { $0.last.flatMap(Double.init) }
        return SMCCodec.clamp(saved ?? fan.current, min: fan.minimum, max: fan.maximum)
    }

    func setManual(_ fan: SMCFan, rpm: Double) {
        let rpm = SMCCodec.clamp(rpm, min: fan.minimum, max: fan.maximum)
        var saved = (UserDefaults.standard.stringArray(forKey: Self.rpmKey) ?? []).filter { !$0.hasPrefix("\(fan.id):") }
        saved.append("\(fan.id):\(Int(rpm))")
        UserDefaults.standard.set(saved, forKey: Self.rpmKey)
        guard let helper = helper() else { return fail() }
        error = nil
        helper.setManual(fan: fan.id, rpm: rpm) { ok in
            DispatchQueue.main.async {
                if ok { self.wanted[fan.id] = rpm; self.requested[fan.id] = Date() } else { self.wanted[fan.id] = nil; self.fail() }
                self.refresh()
            }
        }
    }

    func setAuto(_ id: Int) {
        wanted[id] = nil
        helper()?.setAuto(fan: id) { _ in DispatchQueue.main.async { self.refresh() } }
    }

    func setService(_ label: String, on: Bool, done: @escaping (Bool) -> Void) {
        var finished = false
        let finish = { (ok: Bool) in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                done(ok)
            }
        }
        guard ready, let helper = helper(onError: { finish(false) }) else { return finish(false) }
        helper.setService(label: label, on: on, reply: finish)
    }

    func handOff() {
        wanted.keys.forEach(setAuto)
        connection?.invalidate()
    }

    func install() {
        guard !busy, FileManager.default.fileExists(atPath: Self.bundled.path) else { return fail() }
        busy = true
        error = nil
        let contents: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [Self.binary],
            "MachServices": [Self.label: true],
            "AssociatedBundleIdentifiers": [Self.app],
        ]
        guard let xml = try? PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0),
              let requirement = FanHelperInfo.requirement(identifier: Self.label)
        else { busy = false; return fail() }
        let q = Self.quoted
        let steps = [
            "(\(Self.launchctlPath) bootout system/\(Self.label) >/dev/null 2>&1 || true)",
            "\(Self.mkdirPath) -p \(Self.helperDir)",
            "\(Self.rmPath) -f \(q(Self.binary)) \(q(Self.binary + ".new"))",
            "\(Self.cpPath) \(q(Self.bundled.path)) \(q(Self.binary))",
            "\(Self.chownPath) root:wheel \(q(Self.binary))",
            "\(Self.chmodPath) 755 \(q(Self.binary))",
            "\(Self.codesignPath) --verify \(q("-R=" + requirement)) \(q(Self.binary)) || { \(Self.rmPath) -f \(q(Self.binary)); exit 1; }",
            "\(Self.printfPath) %s \(q(String(decoding: xml, as: UTF8.self).replacingOccurrences(of: "\n", with: ""))) > \(q(Self.plist))",
            "\(Self.chownPath) root:wheel \(q(Self.plist))",
            "\(Self.chmodPath) 644 \(q(Self.plist))",
            "\(Self.launchctlPath) bootstrap system \(q(Self.plist))",
        ]
        let prompt = String(localized: "pikapik wants to change the fan speed and turn services off and on.")
        DispatchQueue.global().async {
            let ok = KeepAwake.runAsAdmin(steps.joined(separator: " && "), prompt: prompt)
            DispatchQueue.main.async {
                self.busy = false
                if ok { self.probe() } else { self.error = String(localized: "Not allowed: no administrator password") }
            }
        }
    }

    func uninstall() {
        guard !busy else { return }
        busy = true
        error = nil
        wanted = [:]
        connection?.invalidate()
        let q = Self.quoted
        let restore = "\(q(Self.binary)) --restore >/dev/null 2>&1 & p=$!; (\(Self.sleepPath) 30; kill $p) >/dev/null 2>&1 & w=$!; wait $p; kill $w 2>/dev/null"
        let command = "\(Self.launchctlPath) bootout system/\(Self.label) >/dev/null 2>&1; [ ! -e \(q(Self.record)) ] || { \(restore); }; \(Self.rmPath) -f \(q(Self.binary)) \(q(Self.binary + ".new")) \(q(Self.record)) \(q(Self.plist))"
        let prompt = String(localized: "pikapik wants to remove administrator access.")
        DispatchQueue.global().async {
            let ok = KeepAwake.runAsAdmin(command, prompt: prompt)
            DispatchQueue.main.async {
                self.busy = false
                if ok { self.ready = false } else { self.error = String(localized: "Not removed: no administrator password") }
                self.refresh()
            }
        }
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func fail() {
        error = String(localized: "Couldn’t change the fan speed. Try allowing administrator access again.")
    }

    private func refresh() {
        guard let smc else { return }
        fans = smc.fans()
        let dropped = wanted.keys.filter { id in
            !(fans.first { $0.id == id }?.manual ?? false) && Date().timeIntervalSince(requested[id] ?? .distantPast) > 3
        }
        guard !dropped.isEmpty else { return }
        dropped.forEach(setAuto)
        error = String(localized: "Fans went back to Auto to keep your Mac safe")
    }

    func probe() {
        guard FileManager.default.fileExists(atPath: Self.binary), let helper = helper() else {
            ready = false
            return
        }
        helper.version { version in
            DispatchQueue.main.async {
                self.ready = version == FanHelperInfo.version
                if self.ready { self.migrate(helper) }
                guard version >= FanHelperInfo.selfUpdating, !self.updated, !FileManager.default.contentsEqual(atPath: Self.binary, andPath: Self.bundled.path) else { return }
                self.updated = true
                helper.update(from: Self.bundled.path) { ok in
                    guard ok, version != FanHelperInfo.version else { return }
                    DispatchQueue.main.async {
                        self.connection?.invalidate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.probe() }
                    }
                }
            }
        }
    }

    private func migrate(_ helper: FanHelperProtocol) {
        guard let old = UserDefaults.standard.stringArray(forKey: Self.oldServicesKey) else { return }
        guard HelperAccess.isAdmin(getuid()) else { return UserDefaults.standard.removeObject(forKey: Self.oldServicesKey) }
        helper.adopt(labels: old) { _ in DispatchQueue.main.async { UserDefaults.standard.removeObject(forKey: Self.oldServicesKey) } }
    }

    static func putBackServices() {
        guard HelperAccess.isAdmin(getuid()), FileManager.default.fileExists(atPath: record), FileManager.default.fileExists(atPath: plist),
              let requirement = FanHelperInfo.requirement(identifier: label)
        else { return }
        let connection = NSXPCConnection(machServiceName: label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        defer { connection.invalidate() }
        let done = DispatchSemaphore(value: 0)
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in done.signal() }) as? FanHelperProtocol else { return }
        helper.restoreServices { _ in done.signal() }
        _ = done.wait(timeout: .now() + 10)
    }

    private func helper(onError: (() -> Void)? = nil) -> FanHelperProtocol? {
        if connection == nil {
            guard let requirement = FanHelperInfo.requirement(identifier: Self.label) else { return nil }
            let new = NSXPCConnection(machServiceName: Self.label, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            new.setCodeSigningRequirement(requirement)
            new.invalidationHandler = { DispatchQueue.main.async { self.connection = nil } }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async { self.ready = false }
            onError?()
        } as? FanHelperProtocol
    }
}
