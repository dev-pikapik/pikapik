import Foundation

let label = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let services = ServiceSwitch(record: "/Library/PrivilegedHelperTools/" + label + FanHelperInfo.recordSuffix, own: label)

if CommandLine.arguments.contains("--restore") {
    guard getuid() == 0 else { exit(1) }
    exit(services.restore(by: 0) ? 0 : 1)
}

let device = SMC()

if CommandLine.arguments.contains("--read") {
    guard let device else { exit(1) }
    let lower = device.read("F0md") != nil
    print("FNum \(device.count)  mode key F0\(lower ? "md" : "Md")  Ftst \(device.hasUnlock ? "yes" : "no")")
    for fan in device.fans() {
        let target = device.read("F\(fan.id)Tg")
        print("F\(fan.id)  Ac \(fan.current)  Mn \(fan.minimum)  Mx \(fan.maximum)  manual \(fan.manual)  Tg type \(target?.type ?? "-")")
    }
    exit(0)
}

final class Service: NSObject, FanHelperProtocol, NSXPCListenerDelegate {
    private let lock = NSLock()
    private let updates = NSLock()
    private let records = NSLock()
    private let overrides = NSLock()
    private let smc: SMC?
    private let services: ServiceSwitch
    private let requirement: String?
    private let candidate: String?
    private var clients = 0

    init(smc: SMC?, services: ServiceSwitch, requirement: String?, candidate: String?) {
        self.smc = smc
        self.services = services
        self.requirement = requirement
        self.candidate = candidate
    }

    func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let smc else { return }
        (0..<smc.count).forEach { smc.setAuto(fan: $0) }
    }

    func guardHeat() {
        lock.lock()
        defer { lock.unlock() }
        guard let smc, ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue,
              smc.fans().contains(where: \.manual)
        else { return }
        (0..<smc.count).forEach { smc.setAuto(fan: $0) }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = self
        lock.lock()
        clients += 1
        lock.unlock()
        var gone = false
        let leave = { [self] in
            lock.lock()
            var last = false
            if !gone {
                gone = true
                clients -= 1
                last = clients == 0
            }
            lock.unlock()
            if last { finish() }
        }
        connection.invalidationHandler = leave
        connection.interruptionHandler = leave
        connection.resume()
        return true
    }

    func version(reply: @escaping (Int) -> Void) {
        reply(FanHelperInfo.version)
    }

    func setManual(fan: Int, rpm: Double, reply: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let cool = ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
        reply(cool && rpm.isFinite && smc?.setManual(fan: fan, rpm: rpm) == true)
    }

    func setAuto(fan: Int, reply: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let smc else { return reply(false) }
        smc.setAuto(fan: fan)
        reply(true)
    }

    func update(from path: String, reply: @escaping (Bool) -> Void) {
        updates.lock()
        defer { updates.unlock() }
        reply(candidate.map { FanHelperInfo.stage(CommandLine.arguments[0], from: path, requirement: $0) } ?? false)
    }

    func setService(label: String, on: Bool, reply: @escaping (Bool) -> Void) {
        guard let caller = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply(false) }
        records.lock()
        defer { records.unlock() }
        reply(services.set(label, on: on, by: caller))
    }

    func adopt(labels: [String], reply: @escaping (Bool) -> Void) {
        guard let caller = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply(false) }
        records.lock()
        defer { records.unlock() }
        reply(services.adopt(labels, by: caller))
    }

    func restoreServices(reply: @escaping (Bool) -> Void) {
        guard let caller = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply(false) }
        records.lock()
        defer { records.unlock() }
        reply(services.restore(by: caller))
    }

    func setScaleModes(vendor: Int, product: Int, sizes: [Int], reply: @escaping (Bool) -> Void) {
        guard let caller = NSXPCConnection.current()?.effectiveUserIdentifier else { return reply(false) }
        overrides.lock()
        defer { overrides.unlock() }
        reply(ScaleOverride().write(vendor: vendor, product: product, sizes: sizes, by: caller))
    }

    func finish() -> Never {
        resetAll()
        updates.lock()
        if let candidate { FanHelperInfo.commit(CommandLine.arguments[0], requirement: candidate) }
        exit(0)
    }
}

let appIdentifier = label.hasSuffix(FanHelperInfo.suffix) ? String(label.dropLast(FanHelperInfo.suffix.count)) : label
let service = Service(smc: device, services: services, requirement: FanHelperInfo.requirement(identifier: appIdentifier), candidate: FanHelperInfo.requirement(identifier: label))
service.resetAll()
services.prune()

let listener = NSXPCListener(machServiceName: label)
listener.delegate = service
listener.resume()

Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in service.guardHeat() }

var signals = [DispatchSourceSignal]()
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { service.finish() }
    source.resume()
    signals.append(source)
}

RunLoop.main.run()
