import Foundation

@main
enum TestServiceGuard {
    static func main() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("test-service-guard-\(UUID().uuidString)").path
        let folder = base + "/LaunchDaemons"
        let outside = base + "/outside"
        for path in [folder + "/sub", outside] { try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(atPath: base) }

        func write(_ path: String, label: String) {
            let data = try! PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0)
            FileManager.default.createFile(atPath: path, contents: data)
        }

        for label in ["com.vendor.daemon", "org.example-x_1.helper", "com.pikapik.e2e.daemon", "A"] {
            precondition(HelperServices.allows(label), label)
        }
        let rejected = [
            "", String(repeating: "a", count: 129), "a/b", "../etc/passwd", "a b", "a;b", "a\nb", "com.vendor.daemon\n", "com.vendör.daemon", "$(id)",
            "com.apple.mdmclient", "COM.APPLE.x", "com.apple.", "com.pikapik.app.direct.fans", "com.pikapik.app.dev.fans", "Com.Pikapik.App.helper",
        ]
        for label in rejected { precondition(!HelperServices.allows(label), "accepted \(label.debugDescription)") }

        write(folder + "/vendor.plist", label: "com.vendor.daemon")
        write(folder + "/renamed-file.plist", label: "com.vendor.other")
        write(folder + "/apple.plist", label: "com.apple.mdmclient")
        write(folder + "/own.plist", label: "com.pikapik.app.direct.fans")
        write(folder + "/sub/nested.plist", label: "com.vendor.nested")
        write(outside + "/target.plist", label: "com.vendor.linked")
        try! FileManager.default.createSymbolicLink(atPath: folder + "/link.plist", withDestinationPath: outside + "/target.plist")
        FileManager.default.createFile(atPath: folder + "/notes.txt", contents: Data("com.vendor.text".utf8))

        precondition(HelperServices.plist(for: "com.vendor.daemon", in: folder) == folder + "/vendor.plist")
        precondition(HelperServices.plist(for: "com.vendor.other", in: folder) == folder + "/renamed-file.plist")
        for label in ["com.vendor.missing", "com.vendor.nested", "com.vendor.linked", "com.vendor.text", "com.apple.mdmclient", "com.pikapik.app.direct.fans", "../outside/target", "vendor"] {
            precondition(HelperServices.plist(for: label, in: folder) == nil, "found \(label)")
        }
        precondition(HelperServices.plist(for: "com.vendor.daemon", in: base + "/missing") == nil)

        precondition(HelperServices.sharing.keys.sorted() == ["com.apple.screensharing", "com.openssh.sshd"])
        precondition(HelperServices.plist(for: "com.openssh.sshd", in: folder) == "/System/Library/LaunchDaemons/ssh.plist")
        precondition(HelperServices.plist(for: "com.apple.screensharing", in: folder) == "/System/Library/LaunchDaemons/com.apple.screensharing.plist")
        for label in ["com.apple.smbd", "com.apple.ftpd", "com.openssh.sshd/x", "com.openssh.sshd "] {
            precondition(HelperServices.plist(for: label, in: folder) == nil, "found \(label)")
        }
        precondition(HelperServices.sharing.values.allSatisfy { $0.hasPrefix("/System/Library/LaunchDaemons/") && !$0.contains("..") })

        print("service allow-list, label check and plist lookup: ok")

        admins()
        switches(base: base, folder: folder)
    }

    static func uid(_ name: String) -> uid_t {
        guard let entry = getpwnam(name) else { fatalError("no user \(name)") }
        return entry.pointee.pw_uid
    }

    static func admins() {
        precondition(HelperAccess.isAdmin(0))
        precondition(!HelperAccess.isAdmin(uid("nobody")))
        precondition(!HelperAccess.isAdmin(uid("daemon")))
        precondition(!HelperAccess.isAdmin(424_242))
        let id = Process()
        let output = Pipe()
        id.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        id.arguments = ["-Gn"]
        id.standardOutput = output
        try! id.run()
        let groups = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(whereSeparator: \.isWhitespace)
        id.waitUntilExit()
        precondition(HelperAccess.isAdmin(getuid()) == groups.contains("admin"), "current user")
        print("administrator check: ok")
    }

    static func switches(base: String, folder: String) {
        let record = base + "/helper.turned-off"
        let own = "com.pikapik.app.direct.fans"
        let standard = uid("nobody")
        var calls: [[String]] = []
        var failing: Set<[String]> = []
        var loaded: Set<String> = []
        var disabled: String? = ""
        let services = ServiceSwitch(record: record, own: own, folder: folder) { arguments in
            calls.append(arguments)
            guard !failing.contains(arguments) else { return nil }
            switch arguments[0] {
            case "print": return loaded.contains(arguments[1]) ? "" : nil
            case "print-disabled": return disabled
            default: return ""
            }
        }
        func saved() -> [String]? {
            FileManager.default.fileExists(atPath: record) ? ServiceSwitch.turnedOff(record) : nil
        }
        func write(_ labels: [String]) {
            try! PropertyListSerialization.data(fromPropertyList: labels, format: .xml, options: 0).write(to: URL(fileURLWithPath: record))
        }
        func reset() {
            calls = []
            failing = []
            try? FileManager.default.removeItem(atPath: record)
        }
        let vendor = "system/com.vendor.daemon"

        for on in [false, true] {
            for label in ["com.vendor.daemon", "com.openssh.sshd", "com.apple.screensharing"] {
                precondition(!services.set(label, on: on, by: standard), "standard user switched \(label)")
            }
            precondition(!services.restore(by: standard) && !services.adopt(["com.openssh.sshd"], by: standard))
        }
        precondition(calls.isEmpty && saved() == nil, "standard user reached launchctl")
        print("standard users are refused: ok")

        for label in [own, "com.apple.mdmclient", "com.vendor.missing", "com.vendor.nested", "com.vendor.linked", "../outside/target"] {
            precondition(!services.set(label, on: false, by: 0) && !services.set(label, on: true, by: 0), label)
        }
        precondition(calls.isEmpty && saved() == nil)

        precondition(services.set("com.vendor.daemon", on: false, by: 0))
        precondition(calls == [["disable", vendor], ["bootout", vendor]])
        precondition(saved() == ["com.vendor.daemon"])
        precondition((try! FileManager.default.attributesOfItem(atPath: record))[.posixPermissions] as? Int == 0o644)
        precondition(services.set("com.vendor.daemon", on: false, by: 0) && saved() == ["com.vendor.daemon"])
        calls = []
        precondition(services.set("com.vendor.daemon", on: true, by: 0))
        precondition(calls == [["enable", vendor], ["bootstrap", "system", folder + "/vendor.plist"]])
        precondition(saved() == [])
        print("turning a daemon off and on keeps the record: ok")

        reset()
        precondition(services.set("com.vendor.other", on: true, by: 0) && saved() == nil, "third-party daemons need no record to turn on")
        reset()
        failing = [["disable", vendor]]
        precondition(!services.set("com.vendor.daemon", on: false, by: 0))
        precondition(saved() == [], "failed turn-off stays out of the record")
        reset()
        write(["com.vendor.daemon"])
        failing = [["disable", vendor]]
        precondition(!services.set("com.vendor.daemon", on: false, by: 0) && saved() == ["com.vendor.daemon"])
        reset()
        failing = [["bootstrap", "system", folder + "/vendor.plist"]]
        loaded = [vendor]
        precondition(services.set("com.vendor.daemon", on: true, by: 0), "already running counts as on")
        loaded = []
        precondition(!services.set("com.vendor.daemon", on: true, by: 0))
        print("failures roll back: ok")

        let ssh = "system/com.openssh.sshd"
        reset()
        precondition(!services.set("com.openssh.sshd", on: true, by: 0) && !services.set("com.apple.screensharing", on: true, by: 0))
        precondition(calls.isEmpty, "sharing turned on without a record")
        precondition(!services.set("com.openssh.sshd", on: false, by: 0))
        precondition(calls == [["print", ssh]] && saved() == nil, "sharing that is already off is not recorded")
        loaded = [ssh]
        calls = []
        precondition(services.set("com.openssh.sshd", on: false, by: 0))
        precondition(calls == [["print", ssh], ["disable", ssh], ["bootout", ssh]] && saved() == ["com.openssh.sshd"])
        calls = []
        precondition(services.set("com.openssh.sshd", on: true, by: 0))
        precondition(calls == [["enable", ssh], ["bootstrap", "system", "/System/Library/LaunchDaemons/ssh.plist"]] && saved() == [])
        precondition(!services.set("com.openssh.sshd", on: true, by: 0), "sharing turned on twice")
        loaded = []
        print("sharing services turn on only from the record: ok")

        reset()
        precondition(services.restore(by: 0) && calls.isEmpty && saved() == nil, "no record, nothing to do")
        write(["com.vendor.daemon", "com.openssh.sshd", own, "com.apple.mdmclient", "com.vendor.gone", "com.apple.screensharing"])
        failing = [["enable", "system/com.vendor.gone"]]
        precondition(!services.restore(by: 0))
        precondition(saved() == ["com.vendor.gone"], "failed entries stay for the next try")
        precondition(calls == [
            ["enable", vendor], ["bootstrap", "system", folder + "/vendor.plist"],
            ["enable", ssh], ["bootstrap", "system", "/System/Library/LaunchDaemons/ssh.plist"],
            ["enable", "system/com.vendor.gone"],
            ["enable", "system/com.apple.screensharing"], ["bootstrap", "system", "/System/Library/LaunchDaemons/com.apple.screensharing.plist"],
        ], "\(calls)")
        failing = []
        calls = []
        precondition(services.restore(by: 0) && saved() == [] && calls == [["enable", "system/com.vendor.gone"]])
        print("restore turns everything back on and clears the record: ok")

        reset()
        disabled = "disabled services = {\n\t\"com.apple.ftpd\" => disabled\n\t\"com.openssh.sshd\" => disabled\n\t\"com.apple.screensharing\" => enabled\n\t\"com.vendor.daemon\" => true\n}\n"
        precondition(services.adopt(["com.openssh.sshd", "com.apple.screensharing", "com.vendor.daemon", "com.openssh.sshd", "com.apple.ftpd"], by: 0))
        precondition(saved() == ["com.openssh.sshd"] && calls == [["print-disabled", "system"]], "migration only records, nothing is switched")
        precondition(!services.adopt(["com.openssh.sshd"], by: 0), "migration runs once")
        reset()
        disabled = nil
        precondition(!services.adopt(["com.openssh.sshd"], by: 0) && saved() == nil)
        print("migration from the old setting: ok")

        reset()
        write(["com.vendor.daemon", "com.openssh.sshd", "com.vendor.other"])
        disabled = "disabled services = {\n\t\"com.openssh.sshd\" => disabled\n\t\"com.vendor.daemon\" => enabled\n\t\"com.vendor.other\" => true\n}\n"
        services.prune()
        precondition(saved() == ["com.openssh.sshd", "com.vendor.other"])
        for text in [nil, "", "garbage\n"] as [String?] {
            disabled = text
            services.prune()
            precondition(saved() == ["com.openssh.sshd", "com.vendor.other"], "pruned without a launchd answer")
        }
        try! "not a plist".write(toFile: record, atomically: true, encoding: .utf8)
        precondition(ServiceSwitch.turnedOff(record) == [] && ServiceSwitch.turnedOff(base + "/missing") == [])
        print("record follows what launchd still has off: ok")

        let displays = base + "/Displays", overrides = displays + "/Overrides"
        let scale = ScaleOverride(base: overrides, owner: getuid(), top: base)
        let fm = FileManager.default
        let put = { (path: String, mark: Bool?) in
            try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let plist: [String: Any] = mark.map { ["DisplayVendorID": 1, "pikapik": $0] } ?? ["DisplayVendorID": 1]
            precondition(fm.createFile(atPath: path, contents: try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)))
        }
        let exists = { (path: String) -> Bool in var info = stat(); return lstat(path, &info) == 0 }
        precondition(scale.removeAll() == 0 && !exists(displays), "no folder: nothing to do")
        let samsung = overrides + "/DisplayVendorID-4c2d/DisplayProductID-730f"
        put(samsung, true)
        for (path, bits) in [(overrides, 0o775), (overrides, 0o757), (displays, 0o777), (base, 0o777), (overrides + "/DisplayVendorID-4c2d", 0o775)] as [(String, mode_t)] {
            chmod(path, bits)
            precondition(scale.files().isEmpty && scale.removeAll() == 0 && exists(samsung), "\(path) others can write: hands off")
            chmod(path, 0o755)
        }
        let mi = overrides + "/DisplayVendorID-61a9/DisplayProductID-2001", foreign = overrides + "/DisplayVendorID-61a9/DisplayProductID-2002"
        put(mi, true)
        put(foreign, nil)
        put(overrides + "/DisplayVendorID-61a9/DisplayProductID-2005", false)
        put(overrides + "/DisplayVendorID-61a9/notes", true)
        put(base + "/elsewhere/DisplayProductID-c4d", true)
        symlink(base + "/elsewhere/DisplayProductID-c4d", overrides + "/DisplayVendorID-61a9/DisplayProductID-2003")
        put(overrides + "/DisplayVendorID-61a9/DisplayProductID-2004/inside", true)
        symlink(base + "/elsewhere", overrides + "/DisplayVendorID-469")
        precondition(scale.files().sorted() == [samsung, mi].sorted(), "\(scale.files())")
        precondition(scale.removeAll() == 2 && !exists(samsung) && !exists(mi) && !exists(overrides + "/DisplayVendorID-4c2d"), "pikapik's files and their empty folder go")
        for path in [foreign, overrides + "/DisplayVendorID-61a9/DisplayProductID-2005", overrides + "/DisplayVendorID-61a9/notes", overrides + "/DisplayVendorID-61a9/DisplayProductID-2003",
                     overrides + "/DisplayVendorID-61a9/DisplayProductID-2004/inside", overrides + "/DisplayVendorID-469", base + "/elsewhere/DisplayProductID-c4d"] {
            precondition(exists(path), "\(path) is not pikapik's: it stays")
        }
        precondition(scale.removeAll() == 0, "the second start finds nothing")
        try! fm.removeItem(atPath: overrides)
        try! fm.createDirectory(atPath: overrides, withIntermediateDirectories: false)
        precondition(scale.removeAll() == 0 && exists(overrides), "a folder pikapik emptied nothing in stays")
        for product in 1...9 { put(overrides + "/DisplayVendorID-2/DisplayProductID-\(product)", true) }
        precondition(scale.removeAll() == ScaleOverride.limit && scale.removeAll() == 1, "8 files at a time")
        precondition(!exists(displays) && exists(base), "the folders left empty go, up to the first one checked")
        print("monitor sizes 1.58.0 added: only pikapik's own files go, within bounds: ok")
    }
}
