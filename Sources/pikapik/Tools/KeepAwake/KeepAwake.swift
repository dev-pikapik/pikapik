import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import SwiftUI

@Observable
final class KeepAwake {
    enum Mode: String {
        case off, timed, indefinitely
    }

    static let shared = KeepAwake()
    static let maxDuration = 365 * 86400
    private static let caffeinatePath = SystemPath.caffeinate
    private static let pmsetPath = SystemPath.pmset
    private static let lidFlagKey = "keep-awake-lid-sleep-disabled"
    private static let legacyUnits = ["minutes": 60, "hours": 3600, "days": 86400, "weeks": 7 * 86400, "months": 30 * 86400]
    private static let sessionKey = "keep-awake-session"
    private static let sessionEndKey = "keep-awake-session-end"
    private static let bridgeKey = "keep-awake-bridge"

    #if APPSTORE
    let hasLid = false
    #else
    let hasLid: Bool = {
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           sources.contains(where: {
               (IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
           }) {
            return true
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(service) }
        return ["AppleClamshellState", "AppleClamshellCausesSleep"].contains(where: {
            IORegistryEntryCreateCFProperty(service, $0 as CFString, kCFAllocatorDefault, 0) != nil
        })
    }()
    #endif

    private(set) var mode = Mode.off
    private(set) var endDate: Date?
    private(set) var now = Date.now
    private(set) var lidActive = false
    private(set) var lidError: String?

    private(set) var lastMode: Mode {
        didSet { UserDefaults.standard.set(lastMode.rawValue, forKey: PreferenceKey.keepAwakeMode) }
    }

    var duration: Int {
        didSet {
            UserDefaults.standard.set(duration, forKey: PreferenceKey.keepAwakeDuration)
            if mode == .timed, duration != oldValue { set(.timed) }
        }
    }

    var keepsDisplayOn: Bool {
        didSet {
            UserDefaults.standard.set(keepsDisplayOn, forKey: PreferenceKey.keepAwakeDisplay)
            update()
        }
    }

    var worksWithLidClosed: Bool {
        get { lidOption }
        set {
            lidOption = newValue
            UserDefaults.standard.set(newValue, forKey: PreferenceKey.keepAwakeLid)
            lidError = nil
            update()
        }
    }

    var stopsOnLowBattery: Bool {
        didSet { UserDefaults.standard.set(stopsOnLowBattery, forKey: PreferenceKey.keepAwakeBattery) }
    }

    private var lidOption: Bool

    @ObservationIgnored private var assertions: [IOPMAssertionID] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let lidFlag = FileManager.default.temporaryDirectory.appendingPathComponent("pikapik-keep-awake")

    private init() {
        let defaults = UserDefaults.standard
        lastMode = Mode(rawValue: defaults.string(forKey: PreferenceKey.keepAwakeMode) ?? "") ?? .timed
        duration = Self.storedDuration()
        keepsDisplayOn = defaults.bool(forKey: PreferenceKey.keepAwakeDisplay)
        lidOption = defaults.bool(forKey: PreferenceKey.keepAwakeLid)
        stopsOnLowBattery = defaults.object(forKey: PreferenceKey.keepAwakeBattery) as? Bool ?? true
    }

    func load() {
        let defaults = UserDefaults.standard
        lastMode = Mode(rawValue: defaults.string(forKey: PreferenceKey.keepAwakeMode) ?? "") ?? .timed
        duration = Self.storedDuration()
        lidOption = defaults.bool(forKey: PreferenceKey.keepAwakeLid)
        keepsDisplayOn = defaults.bool(forKey: PreferenceKey.keepAwakeDisplay)
        stopsOnLowBattery = defaults.object(forKey: PreferenceKey.keepAwakeBattery) as? Bool ?? true
    }

    private static func storedDuration() -> Int {
        let defaults = UserDefaults.standard
        if let unit = defaults.string(forKey: "keep-awake-duration-unit").flatMap({ legacyUnits[$0] }) {
            defaults.set(max(defaults.integer(forKey: "keep-awake-duration-value"), 1) * unit, forKey: PreferenceKey.keepAwakeDuration)
        }
        ["keep-awake-duration-unit", "keep-awake-duration-value"].forEach(defaults.removeObject)
        let seconds = (defaults.object(forKey: PreferenceKey.keepAwakeDuration) as? NSNumber)?.intValue ?? 3600
        return min(max(seconds, 1), maxDuration)
    }

    var isDefault: Bool {
        mode == .off && lastMode == .timed && duration == 3600
            && !keepsDisplayOn && !lidOption && stopsOnLowBattery
    }

    func reset() {
        set(.off)
        lastMode = .timed
        duration = 3600
        keepsDisplayOn = false
        worksWithLidClosed = false
        stopsOnLowBattery = true
    }

    var isOn: Bool {
        get { mode != .off }
        set { set(newValue ? lastMode : .off) }
    }

    var remaining: String? {
        guard mode == .timed else { return nil }
        let end = max(endDate ?? now, now)
        let left = Int(end.timeIntervalSince(now).rounded(.up))
        let days = left / 86400
        let clock = String(format: "%02d:%02d:%02d", left % 86400 / 3600, left % 3600 / 60, left % 60)
        return days > 0
            ? Duration.seconds(days * 86400).formatted(.units(allowed: [.days], width: .narrow)) + " " + clock
            : clock
    }

    var statusText: Text {
        switch mode {
        case .off: return Text("Your Mac sleeps as usual")
        case .indefinitely: return Text("Until you turn it off")
        case .timed:
            let end = max(endDate ?? now, now)
            return Text("\(Text(verbatim: remaining ?? "").monospacedDigit()) left, until \(Self.until(end))")
        }
    }

    static func until(_ end: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(end) {
            let formatter = DateFormatter()
            formatter.doesRelativeDateFormatting = true
            formatter.formattingContext = .middleOfSentence
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: end)
        }
        return calendar.isDateInToday(end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    func set(_ newMode: Mode) {
        mode = newMode
        if newMode != .off { lastMode = newMode }
        now = .now
        endDate = newMode == .timed ? now.addingTimeInterval(TimeInterval(duration)) : nil
        UserDefaults.standard.set(newMode == .off ? nil : newMode.rawValue, forKey: Self.sessionKey)
        UserDefaults.standard.set(endDate, forKey: Self.sessionEndKey)
        update()
    }

    func resume() {
        let defaults = UserDefaults.standard
        Self.stopBridge()
        guard let saved = Mode(rawValue: defaults.string(forKey: Self.sessionKey) ?? ""), saved != .off else { return }
        let end = defaults.object(forKey: Self.sessionEndKey) as? Date
        guard saved == .indefinitely || (end ?? .distantPast) > .now else { return set(.off) }
        mode = saved
        endDate = saved == .timed ? end : nil
        now = .now
        update()
    }

    func suspend() {
        mode = .off
        update()
    }

    func handOff() {
        #if APPSTORE
        return
        #else
        guard mode != .off, MainCopy.canAct else { return }
        let bridge = Process()
        bridge.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        let seconds = min(120, max(1, Int(endDate?.timeIntervalSinceNow ?? 120)))
        bridge.arguments = [keepsDisplayOn ? "-di" : "-i", "-t", String(seconds)]
        guard (try? bridge.run()) != nil else { return }
        UserDefaults.standard.set(Int(bridge.processIdentifier), forKey: Self.bridgeKey)
        #endif
    }

    static func turnOffDisplay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            #if APPSTORE
            let wrangler = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
            defer { IOObjectRelease(wrangler) }
            IORegistryEntrySetCFProperty(wrangler, "IORequestIdle" as CFString, kCFBooleanTrue)
            #else
            _ = try? Process.run(URL(fileURLWithPath: Self.pmsetPath), arguments: ["displaysleepnow"])
            #endif
        }
    }

    private static func stopBridge() {
        #if APPSTORE
        UserDefaults.standard.removeObject(forKey: bridgeKey)
        #else
        let pid = pid_t(UserDefaults.standard.integer(forKey: bridgeKey))
        UserDefaults.standard.removeObject(forKey: bridgeKey)
        guard pid > 0 else { return }
        var name = [CChar](repeating: 0, count: 64)
        proc_name(pid, &name, UInt32(name.count))
        if String(cString: name) == "caffeinate" { kill(pid, SIGTERM) }
        #endif
    }

    private func update() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions = []
        timer?.invalidate()
        timer = nil
        guard mode != .off else { return setLid(false) }

        hold(kIOPMAssertionTypePreventUserIdleSystemSleep)
        if keepsDisplayOn { hold(kIOPMAssertionTypePreventUserIdleDisplaySleep) }
        setLid(hasLid && lidOption)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            KeepAwake.shared.tick()
        }
    }

    private func tick() {
        now = .now
        if let endDate, endDate <= .now {
            set(.off)
        } else if lidActive, stopsOnLowBattery, let level = batteryLevel, level < 20 {
            set(.off)
        }
    }

    private func hold(_ type: String) {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "pikapik Keep Awake" as CFString, &id)
        if result == kIOReturnSuccess { assertions.append(id) }
    }

    #if APPSTORE
    private func setLid(_ on: Bool) {}
    func restoreLidSleepIfNeeded() {}
    #else
    private func setLid(_ on: Bool) {
        guard on != lidActive else { return }
        guard on else {
            try? FileManager.default.removeItem(at: lidFlag)
            lidActive = false
            UserDefaults.standard.set(false, forKey: Self.lidFlagKey)
            return
        }
        let watched = FileManager.default.fileExists(atPath: lidFlag.path) && Self.sleepDisabled
        FileManager.default.createFile(atPath: lidFlag.path, contents: Data(String(ProcessInfo.processInfo.processIdentifier).utf8))
        if watched {
            lidActive = true
            UserDefaults.standard.set(true, forKey: Self.lidFlagKey)
            return
        }
        let flag = "'" + lidFlag.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(Self.pmsetPath) -a disablesleep 1 || exit 1; (g=0; while [ -e \(flag) ]; do if /bin/kill -0 \"$(/bin/cat \(flag))\"; then g=0; else g=$((g+2)); [ $g -ge 60 ] && break; fi; /bin/sleep 2; done; \(Self.pmsetPath) -a disablesleep 0; /bin/rm -f \(flag)) >/dev/null 2>&1 &"
        if Self.runAsAdmin(command, prompt: String(localized: "pikapik wants to keep your Mac awake with the lid closed.")) {
            lidActive = true
            UserDefaults.standard.set(true, forKey: Self.lidFlagKey)
        } else {
            try? FileManager.default.removeItem(at: lidFlag)
            lidOption = false
            UserDefaults.standard.set(false, forKey: PreferenceKey.keepAwakeLid)
            lidError = String(localized: "Not turned on: no administrator password")
        }
    }

    func restoreLidSleepIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.lidFlagKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !self.lidActive else { return }
            if Self.sleepDisabled {
                _ = Self.runAsAdmin("\(Self.pmsetPath) -a disablesleep 0", prompt: String(localized: "pikapik wants to let your Mac sleep with the lid closed again."))
            }
            UserDefaults.standard.set(false, forKey: Self.lidFlagKey)
        }
    }

    private static var sleepDisabled: Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.pmsetPath)
        process.arguments = ["-g"]
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return false }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output.split(separator: "\n").contains {
            $0.contains("SleepDisabled") && $0.split(whereSeparator: \.isWhitespace).last == "1"
        }
    }

    static func runAsAdmin(_ command: String, prompt: String) -> Bool {
        runScript("do shell script \(scriptQuoted(command)) with prompt \(scriptQuoted(prompt)) with administrator privileges").error == 0
    }

    static func runScript(_ source: String) -> (text: String?, error: Int) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (result?.stringValue, error.map { $0[NSAppleScript.errorNumber] as? Int ?? -1 } ?? 0)
    }

    static func scriptQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    #endif

    private var batteryLevel: Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return current * 100 / max
        }
        return nil
    }
}


extension KeepAwake {
    func handle(_ url: URL) {
        guard MainCopy.canAct else { return MainCopy.shared.whenMain { [self] in handle(url) } }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name
        func flag(_ current: Bool) -> Bool { value == "on" ? true : value == "off" ? false : !current }
        switch url.host {
        case "keep-awake":
            isOn = flag(isOn)
        case "lid-closed":
            let on = flag(isOn && worksWithLidClosed)
            worksWithLidClosed = on
            if on { isOn = true }
        case "display":
            let on = flag(isOn && keepsDisplayOn)
            keepsDisplayOn = on
            if on { isOn = true }
        default:
            break
        }
    }
}
