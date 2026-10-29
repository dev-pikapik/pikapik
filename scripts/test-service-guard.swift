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
        precondition(ScaleOverride.relative(vendor: 0x61A9, product: 0x2001) == "DisplayVendorID-61a9/DisplayProductID-2001")
        precondition(ScaleOverride.relative(vendor: 0x469, product: 0xC4D) == "DisplayVendorID-469/DisplayProductID-c4d", "lowercase, no padding, as CoreDisplay")
        let entries = { (bytes: Data) -> [String] in
            let plist = try! PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
            precondition(plist["pikapik"] as? Bool == true && plist.count == 4, "\(plist)")
            return (plist["scale-resolutions"] as! [Data]).map { $0.base64EncodedString() }
        }
        let mi = [2752, 1152, 2294, 960, 1966, 823]
        precondition(entries(ScaleOverride.data(vendor: 0x61A9, product: 0x2001, sizes: mi)!)
            == ["AAAVgAAACQAAAAABACAAAA==", "AAAR7AAAB4AAAAABACAAAA==", "AAAPXAAABm4AAAABACAAAA=="], "the Mi's file, entry for entry as Apple's")
        // The file macOS took on 29.10 for the Samsung, byte for byte.
        let samsung = [2548, 1067, 2294, 960, 1966, 823]
        let bytes = ScaleOverride.data(vendor: 0x4C2D, product: 0x730F, sizes: samsung)!
        precondition(bytes == Data(base64Encoded: "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VOIiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPgo8ZGljdD4KCTxrZXk+RGlzcGxheVByb2R1Y3RJRDwva2V5PgoJPGludGVnZXI+Mjk0NTU8L2ludGVnZXI+Cgk8a2V5PkRpc3BsYXlWZW5kb3JJRDwva2V5PgoJPGludGVnZXI+MTk1MDE8L2ludGVnZXI+Cgk8a2V5PnBpa2FwaWs8L2tleT4KCTx0cnVlLz4KCTxrZXk+c2NhbGUtcmVzb2x1dGlvbnM8L2tleT4KCTxhcnJheT4KCQk8ZGF0YT4KCQlBQUFUNkFBQUNGWUFBQUFCQUNBQUFBPT0KCQk8L2RhdGE+CgkJPGRhdGE+CgkJQUFBUjdBQUFCNEFBQUFBQkFDQUFBQT09CgkJPC9kYXRhPgoJCTxkYXRhPgoJCUFBQVBYQUFBQm00QUFBQUJBQ0FBQUE9PQoJCTwvZGF0YT4KCTwvYXJyYXk+CjwvZGljdD4KPC9wbGlzdD4K"), "\(bytes.base64EncodedString())")
        precondition(String(data: bytes, encoding: .utf8)!.contains("<key>pikapik</key>"), "uninstall greps the marker")
        for sizes in [[], [2294], [2294, 960, 1], [639, 960], [3361, 960], [2294, 599], [2294, 3361], Array(repeating: 1000, count: 18)] {
            precondition(ScaleOverride.data(vendor: 0x4C2D, product: 0x730F, sizes: sizes) == nil, "\(sizes) refused")
        }
        precondition(ScaleOverride.data(vendor: 0x4C2D, product: 0x730F, sizes: Array(repeating: 1000, count: 16)) != nil, "8 sizes at most")
        for (vendor, product) in [(0, 1), (0x10000, 1), (-1, 1), (1, 0x10000), (1, -1)] {
            precondition(ScaleOverride.data(vendor: vendor, product: product, sizes: samsung) == nil, "\(vendor)-\(product) refused")
        }
        let file = overrides + "/DisplayVendorID-4c2d/DisplayProductID-730f"
        precondition(!scale.write(vendor: 0x4C2D, product: 0x730F, sizes: samsung, by: 4242), "a non-admin caller writes nothing")
        precondition(!scale.write(vendor: 0x4C2D, product: 0x730F, sizes: samsung, by: uid_t(bitPattern: -2)) && !fm.fileExists(atPath: displays), "nor does nobody")
        precondition(scale.write(vendor: 0x4C2D, product: 0x730F, sizes: samsung, by: 0) && fm.contents(atPath: file) == bytes)
        let mode = { (path: String) -> mode_t in var info = stat(); lstat(path, &info); return info.st_mode }
        precondition(mode(file) & 0o7777 == 0o644 && mode(overrides) & 0o7777 == 0o755 && mode(displays + "/Overrides/DisplayVendorID-4c2d") & 0o7777 == 0o755)
        let inode = { (path: String) -> ino_t in var info = stat(); lstat(path, &info); return info.st_ino }
        let first = inode(file)
        precondition(scale.write(vendor: 0x4C2D, product: 0x730F, sizes: samsung, by: 0) && inode(file) == first, "the same sizes are not written again")
        precondition(scale.write(vendor: 0x4C2D, product: 0x730F, sizes: [2294, 960], by: 0) && inode(file) != first, "its own file is replaced")
        let foreign = overrides + "/DisplayVendorID-61a9/DisplayProductID-2001"
        try! fm.createDirectory(atPath: (foreign as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! "<plist><dict/></plist>".write(toFile: foreign, atomically: true, encoding: .utf8)
        precondition(!scale.write(vendor: 0x61A9, product: 0x2001, sizes: samsung, by: 0) && fm.contents(atPath: foreign) == Data("<plist><dict/></plist>".utf8),
                     "a hand-made file stays")
        symlink(file, overrides + "/DisplayVendorID-61a9/DisplayProductID-2002")
        precondition(!scale.write(vendor: 0x61A9, product: 0x2002, sizes: samsung, by: 0) && fm.contents(atPath: file) == ScaleOverride.data(vendor: 0x4C2D, product: 0x730F, sizes: [2294, 960]),
                     "a symlink is never written through")
        try! fm.createDirectory(atPath: overrides + "/DisplayVendorID-61a9/DisplayProductID-2003", withIntermediateDirectories: false)
        precondition(!scale.write(vendor: 0x61A9, product: 0x2003, sizes: samsung, by: 0), "a folder in the file's place stays")
        try! fm.createDirectory(atPath: base + "/elsewhere", withIntermediateDirectories: false)
        symlink(base + "/elsewhere", overrides + "/DisplayVendorID-469")
        precondition(!scale.write(vendor: 0x469, product: 0xC4D, sizes: samsung, by: 0) && (try! fm.contentsOfDirectory(atPath: base + "/elsewhere")).isEmpty,
                     "a symlinked folder is never written through")
        for (path, bits) in [(overrides, 0o775), (overrides, 0o757), (displays, 0o777)] as [(String, mode_t)] {
            chmod(path, bits)
            precondition(!scale.write(vendor: 0x1, product: 0x1, sizes: samsung, by: 0), "\(path) others can write is refused")
            chmod(path, 0o755)
        }
        precondition(!fm.fileExists(atPath: overrides + "/DisplayVendorID-1/DisplayProductID-1"))
        for product in 1...7 { precondition(scale.write(vendor: 0x2, product: product, sizes: samsung, by: 0), "file \(product + 1)") }
        precondition(!scale.write(vendor: 0x3, product: 0x1, sizes: samsung, by: 0), "a 9th file is refused")
        precondition(scale.write(vendor: 0x4C2D, product: 0x730F, sizes: samsung, by: 0), "one of the 8 is still replaced")
        print("monitor sizes: only pikapik's own file is written, within bounds: ok")
    }
}
