import CommonCrypto
import Darwin.membership
import Foundation
import Security

@objc protocol FanHelperProtocol {
    func version(reply: @escaping (Int) -> Void)
    func setManual(fan: Int, rpm: Double, reply: @escaping (Bool) -> Void)
    func setAuto(fan: Int, reply: @escaping (Bool) -> Void)
    func update(from path: String, reply: @escaping (Bool) -> Void)
    func setService(label: String, on: Bool, reply: @escaping (Bool) -> Void)
    func adopt(labels: [String], reply: @escaping (Bool) -> Void)
    func restoreServices(reply: @escaping (Bool) -> Void)
    /// Writes or replaces pikapik's override for one monitor model; sizes are looks-like points, w,h pairs.
    func setScaleModes(vendor: Int, product: Int, sizes: [Int], reply: @escaping (Bool) -> Void)
}

enum HelperAccess {
    static func isAdmin(_ uid: uid_t) -> Bool {
        guard uid != 0 else { return true }
        var user = [UInt8](repeating: 0, count: 16), admin = [UInt8](repeating: 0, count: 16)
        var member: Int32 = 0
        return mbr_uid_to_uuid(uid, &user) == 0 && mbr_gid_to_uuid(80, &admin) == 0
            && mbr_check_membership(user, admin, &member) == 0 && member == 1
    }
}

struct ServiceSwitch {
    private static let launchctlExecutableURL = URL(fileURLWithPath: "/bin/launchctl")
    let record: String
    let own: String
    var folder = HelperServices.folder
    var launchctl: ([String]) -> String? = ServiceSwitch.run

    static func turnedOff(_ record: String) -> [String] {
        FileManager.default.contents(atPath: record).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String] ?? []
    }

    func set(_ label: String, on: Bool, by caller: uid_t) -> Bool {
        guard HelperAccess.isAdmin(caller), label != own, let file = HelperServices.plist(for: label, in: folder) else { return false }
        let target = "system/" + label
        let labels = Self.turnedOff(record)
        let sharing = HelperServices.sharing[label] != nil
        if on {
            guard !sharing || labels.contains(label), launchctl(["enable", target]) != nil else { return false }
            if labels.contains(label) { _ = save(labels.filter { $0 != label }) }
            return launchctl(["bootstrap", "system", file]) != nil || launchctl(["print", target]) != nil
        }
        guard !sharing || launchctl(["print", target]) != nil else { return false }
        let added = !labels.contains(label)
        guard !added || save(labels + [label]) else { return false }
        guard launchctl(["disable", target]) != nil else {
            if added { _ = save(labels) }
            return false
        }
        _ = launchctl(["bootout", target])
        return true
    }

    func restore(by caller: uid_t) -> Bool {
        guard HelperAccess.isAdmin(caller) else { return false }
        let labels = Self.turnedOff(record)
        let left = labels.filter { label in
            guard label != own, HelperServices.allows(label) || HelperServices.sharing[label] != nil else { return false }
            guard launchctl(["enable", "system/" + label]) != nil else { return true }
            if let file = HelperServices.plist(for: label, in: folder) { _ = launchctl(["bootstrap", "system", file]) }
            return false
        }
        return (left == labels || save(left)) && left.isEmpty
    }

    func adopt(_ labels: [String], by caller: uid_t) -> Bool {
        guard HelperAccess.isAdmin(caller), !FileManager.default.fileExists(atPath: record), let disabled = disabled() else { return false }
        return save(labels.reduce(into: [String]()) { kept, label in
            if HelperServices.sharing[label] != nil, disabled.contains(label), !kept.contains(label) { kept.append(label) }
        })
    }

    func prune() {
        let labels = Self.turnedOff(record)
        guard !labels.isEmpty, let disabled = disabled(), !disabled.isEmpty else { return }
        let kept = labels.filter(disabled.contains)
        if kept != labels { _ = save(kept) }
    }

    private func disabled() -> Set<String>? {
        launchctl(["print-disabled", "system"]).map { text in
            Set(text.split(separator: "\n").compactMap { line -> String? in
                let item = line.trimmingCharacters(in: .whitespaces)
                guard item.hasPrefix("\""), let end = item.range(of: "\" => "), ["disabled", "true"].contains(String(item[end.upperBound...])) else { return nil }
                return String(item[item.index(after: item.startIndex)..<end.lowerBound])
            })
        }
    }

    private func save(_ labels: [String]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: labels, format: .xml, options: 0),
              (try? data.write(to: URL(fileURLWithPath: record), options: .atomic)) != nil
        else { return false }
        _ = chown(record, 0, 0)
        return chmod(record, 0o644) == 0
    }

    static func run(_ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = launchctlExecutableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

enum HelperServices {
    static let folder = "/Library/LaunchDaemons"
    static let sharing = [
        "com.openssh.sshd": "/System/Library/LaunchDaemons/ssh.plist",
        "com.apple.screensharing": "/System/Library/LaunchDaemons/com.apple.screensharing.plist",
    ]
    private static let reserved = ["com.apple.", "com.pikapik.app.direct", "com.pikapik.app"]
    private static let characters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    static func allows(_ label: String) -> Bool {
        let lower = label.lowercased()
        return (1...128).contains(label.utf8.count) && label.unicodeScalars.allSatisfy(characters.contains) && !reserved.contains(where: lower.hasPrefix)
    }

    static func plist(for label: String, in folder: String = folder) -> String? {
        if let path = sharing[label] { return path }
        guard allows(label), let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return nil }
        return names.sorted().filter { $0.hasSuffix(".plist") }.map { folder + "/" + $0 }.first { path in
            (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular
                && NSDictionary(contentsOfFile: path)?["Label"] as? String == label
        }
    }
}

enum FanHelperInfo {
    static let version = 5
    static let selfUpdating = 2
    static let suffix = ".fans"
    static let recordSuffix = ".turned-off"
    static let appIdentifier = "com.pikapik.app.direct"

    static func requirement(identifier: String) -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        guard let leaf = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first else { return nil }
        let data = SecCertificateCopyData(leaf) as Data
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        let hash = digest.map { String(format: "%02X", $0) }.joined()
        return "identifier \"\(identifier)\" and certificate leaf = H\"\(hash)\""
    }

    static func build(_ path: String, requirement: String? = nil) -> Int? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        if let requirement {
            var compiled: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess, let compiled,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), compiled) == errSecSuccess
            else { return nil }
        }
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let plist = (info as? [String: Any])?[kSecCodeInfoPList as String] as? [String: Any],
              let build = plist["CFBundleVersion"] as? String
        else { return nil }
        return Int(build)
    }

    static func stage(_ target: String, from source: String, requirement: String) -> Bool {
        let staged = target + ".new"
        unlink(staged)
        guard let data = FileManager.default.contents(atPath: source),
              FileManager.default.createFile(atPath: staged, contents: data, attributes: [.posixPermissions: 0o755]),
              let candidate = build(staged, requirement: requirement), candidate >= build(target) ?? 0
        else {
            unlink(staged)
            return false
        }
        return true
    }

    @discardableResult
    static func commit(_ target: String, requirement: String) -> Bool {
        let staged = target + ".new"
        guard let candidate = build(staged, requirement: requirement), candidate >= build(target) ?? 0,
              rename(staged, target) == 0
        else {
            unlink(staged)
            return false
        }
        return true
    }
}

/// A monitor model's extra HiDPI sizes, in the folder CoreDisplay reads on the next enumeration of that monitor.
struct ScaleOverride {
    static let marker = "pikapik"
    static let system = "/System/Library/Displays/Contents/Resources/Overrides"
    static let limit = 8 // pikapik files on one Mac
    var base = "/Library/Displays/Contents/Resources/Overrides" // tests pass a temp folder
    var owner: uid_t = 0 // tests pass getuid()
    var top = "/Library" // the first folder checked; tests pass their temp folder

    static func relative(vendor: Int, product: Int) -> String {
        String(format: "DisplayVendorID-%x/DisplayProductID-%x", vendor, product) // lowercase, no padding, as CoreDisplay
    }

    static func valid(vendor: Int, product: Int, sizes: [Int]) -> Bool {
        (1...0xFFFF).contains(vendor) && (0...0xFFFF).contains(product)
            && sizes.count % 2 == 0 && (2...2 * limit).contains(sizes.count)
            && stride(from: 0, to: sizes.count, by: 2).allSatisfy { (640...3360).contains(sizes[$0]) && (600...3360).contains(sizes[$0 + 1]) }
    }

    /// XML, so uninstall finds the marker with grep. Each entry: big-endian {2w, 2h, 0x1, 0x200000}, as Apple's.
    static func data(vendor: Int, product: Int, sizes: [Int]) -> Data? {
        guard valid(vendor: vendor, product: product, sizes: sizes) else { return nil }
        let entries = stride(from: 0, to: sizes.count, by: 2).map { i -> Data in
            [UInt32(2 * sizes[i]), UInt32(2 * sizes[i + 1]), 1, 0x0020_0000].reduce(into: Data()) { d, v in
                withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
            }
        }
        let plist: [String: Any] = ["DisplayVendorID": vendor, "DisplayProductID": product, marker: true, "scale-resolutions": entries]
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    func write(vendor: Int, product: Int, sizes: [Int], by caller: uid_t) -> Bool {
        let rel = Self.relative(vendor: vendor, product: product), path = base + "/" + rel
        guard HelperAccess.isAdmin(caller), let data = Self.data(vendor: vendor, product: product, sizes: sizes),
              !FileManager.default.fileExists(atPath: Self.system + "/" + rel), // never shadow Apple's file
              folders(for: (path as NSString).deletingLastPathComponent) else { return false }
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, ours(path) else { return false } // foreign or odd file: hands off
            if FileManager.default.contents(atPath: path) == data { return true }
        } else if files().count >= Self.limit { return false }
        guard (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil else { return false }
        return chown(path, owner, gid_t.max) == 0 && chmod(path, 0o644) == 0 // root:wheel 0644, the group from the folder
    }

    /// Every component from `top` down: a real directory owned by `owner`, writable by nobody else; missing ones are made 0755.
    private func folders(for dir: String) -> Bool {
        var path = ""
        for part in dir.split(separator: "/") {
            path += "/" + part
            guard path.count >= top.count else { continue }
            var info = stat()
            if lstat(path, &info) != 0 {
                guard errno == ENOENT, mkdir(path, 0o755) == 0, chown(path, owner, gid_t.max) == 0, // group from the parent: wheel under /Library
                      chmod(path, 0o755) == 0,
                      lstat(path, &info) == 0 else { return false }
            }
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == owner, info.st_mode & 0o022 == 0 else { return false }
        }
        return true
    }

    private func ours(_ path: String) -> Bool { (NSDictionary(contentsOfFile: path)?[Self.marker] as? Bool) == true }

    private func files() -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: base)) ?? []).filter { $0.hasPrefix("DisplayVendorID-") }.flatMap { vendor in
            ((try? fm.contentsOfDirectory(atPath: base + "/" + vendor)) ?? []).filter { $0.hasPrefix("DisplayProductID-") }.map { base + "/" + vendor + "/" + $0 }
        }.filter { path in
            var info = stat()
            return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && ours(path)
        }
    }
}
