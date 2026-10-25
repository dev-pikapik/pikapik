import Foundation
import Security
import CoreServices

enum LeftoverKind: Int, CaseIterable, Comparable {
    case app, appData, containers, caches, preferences, background, extensions, logs, install

    static func < (a: LeftoverKind, b: LeftoverKind) -> Bool { a.rawValue < b.rawValue }
}

enum LeftoverReason: Equatable {
    case bundle
    case byID(String)
    case byName
    case appGroup(String)
    case launchJob(String)
    case helper(String)
    case receipt(String)
    case cliLink
    case homebrew(String)
    case vendor
    case related
}

struct Leftover: Identifiable, Equatable {
    var url: URL
    var kind: LeftoverKind
    var reason: LeftoverReason
    var preselected: Bool
    var sharedWith: [String] = []
    var needsAdmin = false
    var device: Int32 = 0
    var inode: UInt64 = 0
    var isLink = false
    var jobLabel: String?
    var isDaemon = false
    var packageID: String?
    var size: Int64?

    var id: String { url.path }
}

struct OrphanGroup: Identifiable, Equatable {
    var id: String
    var name: String
    var items: [Leftover]
    var newest: Date
}

enum AppNames {
    static let caskroomPaths = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
    static let pkgutilPath = "/usr/sbin/pkgutil"
    static let appleBundleIDPrefix = "com.apple."
    static let systemAppFolders = [
        "System/Applications", "System/Applications/Utilities", "System/Library/CoreServices",
        "System/Library/CoreServices/Applications", "System/Cryptexes/App/System/Applications",
        "Applications", "Applications/Utilities",
    ]
    static let generic: Set<String> = [
        "helper", "helpers", "updater", "update", "agent", "agents", "support", "data", "common", "shared", "app", "apps", "application",
        "applications", "plugin", "plugins", "extension", "extensions", "cache", "caches", "log", "logs", "backup", "backups", "service",
        "services", "daemon", "launcher", "installer", "uninstaller", "setup", "library", "settings", "preferences", "resources", "tools",
        "tool", "utilities", "utility", "desktop", "client", "server", "mac", "macos", "electron", "temp", "tmp", "default", "main", "core",
        "base", "assets", "storage", "database", "sync", "crash", "reports", "report", "framework", "frameworks", "metadata", "config",
    ]
    static let system: Set<String> = [
        "mobilesync", "addressbook", "clouddocs", "fileprovider", "knowledge", "icloud", "callhistorydb", "callhistorytransactions",
        "syncservices", "diskimages", "crashreporter", "dock", "icdd", "accountsd", "cloudkit", "animoji",
    ]
    static let genericVendors: Set<String> = ["apple", "github", "gitlab", "electron", "electronjs", "sparkleproject", "chromium", "squirrel"]
    static let ignoredNested = ["org.sparkle-project.", "com.github.electron", "com.github.squirrel"]
    static let separators: Set<Character> = [" ", "-", "_"]

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func squash(_ text: String) -> String {
        fold(text).filter { !separators.contains($0) }
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
    }

    static func usable(_ squashed: String, blocked: Set<String> = []) -> Bool {
        guard !squashed.isEmpty, !generic.contains(squashed), !system.contains(squashed), !blocked.contains(squashed) else { return false }
        return squashed.count >= 3 || (squashed.count == 2 && squashed.allSatisfy(isCJK))
    }

    static func nameKeys(_ names: [String], blocked: Set<String> = []) -> Set<String> {
        Set(names.map(squash).filter { usable($0, blocked: blocked) })
    }

    static func vendors(bundleID: String, organization: String) -> [String] {
        var found: [String] = []
        let parts = bundleID.split(separator: ".").map(String.init)
        if parts.count >= 3 { found.append(parts[1]) }
        let words = organization.split(whereSeparator: { $0 == " " || $0 == "," })
        if let first = words.first(where: { $0.lowercased() != "the" }) { found.append(String(first)) }
        var seen = Set<String>()
        return found.filter { vendor in
            let key = squash(vendor)
            return key.count >= 3 && !genericVendors.contains(key) && !generic.contains(key) && !system.contains(key)
                && key.allSatisfy { $0.isLetter || $0.isNumber } && seen.insert(key).inserted
        }
    }

    static func twoParts(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func isIgnoredNested(_ id: String) -> Bool {
        let lower = id.lowercased()
        return ignoredNested.contains { lower.hasPrefix($0) }
    }

    static func dottedPrefixes(_ text: String) -> [String] {
        var found = [text]
        var end = text.endIndex
        while let dot = text[..<end].lastIndex(of: ".") {
            found.append(String(text[..<dot]))
            end = dot
        }
        return found
    }

    static func idForms(_ entry: String) -> [String] {
        var forms = [entry.lowercased()]
        var rest = entry
        if let team = rest.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) {
            rest.removeSubrange(team)
            forms.append(rest.lowercased())
        }
        if rest.lowercased().hasPrefix("group.") { forms.append(String(rest.lowercased().dropFirst(6))) }
        return forms
    }

    static func nameBoundaries(_ entry: String) -> [String] {
        var found: [String] = []
        var squashed = ""
        for (index, character) in fold(entry).enumerated() {
            if index > 0, squashed.count >= 5, separators.contains(character) || character == "." || character.isNumber { found.append(squashed) }
            if !separators.contains(character) { squashed.append(character) }
        }
        return found
    }

    static func processName(_ entry: String) -> String? {
        let stamps = ["_[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\\.plist$", "[-_][0-9]{4}(-[0-9]{2}){2}-[0-9]{6}([._].*)?$"]
        for stamp in stamps {
            if let range = entry.range(of: stamp, options: .regularExpression), range.lowerBound > entry.startIndex { return String(entry[..<range.lowerBound]) }
        }
        return nil
    }

    static func isApple(_ forms: [String]) -> Bool {
        forms.contains { $0.hasPrefix("com.apple.") || $0.hasPrefix("systemgroup.") }
    }

    static func isIDShaped(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let top = parts.first, top.count <= 3, top.first?.isLetter == true else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
    }

    static func orphanID(_ entry: String) -> String? {
        var name = entry
        for suffix in [".plist", ".savedState", ".binarycookies", ".sfl2", ".sfl3", ".sfl4", ".sfl"] where name.lowercased().hasSuffix(suffix.lowercased()) {
            name.removeLast(suffix.count)
            break
        }
        if let uuid = name.range(of: "\\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$", options: .regularExpression) {
            name.removeSubrange(uuid)
        }
        if let team = name.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) { name.removeSubrange(team) }
        if name.lowercased().hasPrefix("group.") { name.removeFirst(6) }
        return isIDShaped(name) ? name : nil
    }

    static func orphanTitle(_ id: String) -> String {
        let tails: Set<String> = ["app", "mac", "macos", "osx", "desktop", "client", "helper", "agent", "xos"]
        let parts = id.split(separator: ".").map(String.init)
        for part in parts.dropFirst().reversed() {
            var words = part.split { $0 == "-" || $0 == "_" }.map(String.init)
            while let last = words.last, tails.contains(last.lowercased()), words.count > 1 { words.removeLast() }
            if words.count == 1, tails.contains(words[0].lowercased()) { continue }
            let title = words.map { word in word.prefix(1).uppercased() + word.dropFirst() }.joined(separator: " ")
            return isClear(title) ? title : id
        }
        return id
    }

    private static func isClear(_ title: String) -> Bool {
        title.filter(\.isLetter).count >= 4 && title.filter(\.isNumber).count * 2 <= title.count && !generic.contains(squash(title))
    }
}

struct AppIdentity: Equatable, Identifiable {
    var url: URL
    var bundleID: String
    var names: [String] = []
    var executables: [String] = []
    var version = ""
    var nestedIDs: [String] = []
    var helperLabels: [String] = []
    var teamID = ""
    var groups: [String] = []
    var organization = ""
    var isAppStore = false
    var isPlatform = false

    var id: String { url.path }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var vendors: [String] { AppNames.vendors(bundleID: bundleID, organization: organization) }
    var isOwn: Bool { bundleID.lowercased().hasPrefix(AppConstants.bundleIDPrefix) }

    private var usableNested: [String] {
        nestedIDs.filter { $0.contains(".") && !AppNames.isIgnoredNested($0) }
    }

    var strongIDs: [String] {
        let own = AppNames.twoParts(bundleID)
        return AppIdentity.unique(([bundleID] + usableNested.filter { AppNames.twoParts($0) == own }).filter { $0.contains(".") })
    }

    var looseIDs: [String] {
        let strong = Set(strongIDs.map { $0.lowercased() })
        return AppIdentity.unique(usableNested.filter { !strong.contains($0.lowercased()) })
    }

    var ids: [String] { strongIDs + looseIDs }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static let nestedFolders = ["Library/LoginItems", "Library/SystemExtensions", "XPCServices", "PlugIns", "Helpers", "Frameworks"]
    private static let nestedExtensions: Set<String> = ["app", "appex", "xpc", "bundle", "plugin", "systemextension", "prefpane", "qlgenerator", "mdimporter"]

    private static func plist(_ url: URL) -> [String: Any] {
        NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
    }

    private static func text(_ value: Any?) -> String {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.contains("$(") else { return "" }
        return string
    }

    private static func nestedBundles(in app: URL) -> (bundles: [URL], labels: [String]) {
        let fm = FileManager.default
        let contents = app.appendingPathComponent("Contents")
        var bundles: [URL] = []
        for folder in nestedFolders {
            let dir = contents.appendingPathComponent(folder)
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix(".") {
                let url = dir.appendingPathComponent(name)
                let ext = url.pathExtension.lowercased()
                if folder == "Frameworks" ? ext == "app" : nestedExtensions.contains(ext) {
                    bundles.append(url)
                } else if folder == "Library/LoginItems", ext != "app" {
                    for inner in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where inner.lowercased().hasSuffix(".app") {
                        bundles.append(url.appendingPathComponent(inner))
                    }
                }
            }
        }
        let services = contents.appendingPathComponent("Library/LaunchServices")
        let labels = ((try? fm.contentsOfDirectory(atPath: services.path)) ?? []).filter { !$0.hasPrefix(".") && !$0.hasSuffix(".plist") }.sorted()
        return (Array(bundles.prefix(128)), labels)
    }

    static func signature(of url: URL) -> (team: String, groups: [String], organization: String, platform: Bool)? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        var team = dict[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
        if team.isEmpty, let identifier = (entitlements["com.apple.application-identifier"] ?? entitlements["application-identifier"]) as? String,
           let prefix = identifier.split(separator: ".").first, prefix.count == 10 {
            team = String(prefix)
        }
        var organization = ""
        if let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String?, let colon = summary.range(of: ": ") {
            organization = String(summary[colon.upperBound...])
            if let paren = organization.range(of: " (", options: .backwards) { organization = String(organization[..<paren.lowerBound]) }
        }
        let platform = (dict[kSecCodeInfoPlatformIdentifier as String] as? Int ?? 0) != 0
        return (team, entitlements["com.apple.security.application-groups"] as? [String] ?? [], organization, platform)
    }

    static func read(at url: URL, signed: Bool = true) -> AppIdentity? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard url.pathExtension.lowercased() == "app", fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let info = plist(url.appendingPathComponent("Contents/Info.plist"))
        var app = AppIdentity(url: url, bundleID: text(info["CFBundleIdentifier"]))
        app.version = text(info["CFBundleShortVersionString"])
        let executable = text(info["CFBundleExecutable"])
        app.names = unique([url.deletingPathExtension().lastPathComponent, text(info["CFBundleDisplayName"]), text(info["CFBundleName"]), executable])
        var executables = [executable]
        var labels = Array((info["SMPrivilegedExecutables"] as? [String: Any] ?? [:]).keys)
        var nestedIDs: [String] = []
        let nested = nestedBundles(in: url)
        for bundle in nested.bundles {
            let inner = plist(bundle.appendingPathComponent("Contents/Info.plist"))
            nestedIDs.append(text(inner["CFBundleIdentifier"]))
            executables.append(text(inner["CFBundleExecutable"]))
            labels += Array((inner["SMPrivilegedExecutables"] as? [String: Any] ?? [:]).keys)
        }
        app.executables = unique(executables)
        app.nestedIDs = unique(nestedIDs).filter { !AppNames.isIgnoredNested($0) }
        app.helperLabels = unique(labels + nested.labels).sorted()
        app.isAppStore = fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
        if signed, let main = signature(of: url) {
            app.teamID = main.team
            app.organization = main.organization
            app.isPlatform = main.platform
            app.groups = unique(main.groups + nested.bundles.flatMap { signature(of: $0)?.groups ?? [] })
        }
        return app
    }
}

struct AppRoots {
    var home: URL
    var root: URL
    var userCache: URL?
    var userTemp: URL?
    var caskrooms: [URL]
    var pkgutil: ([String]) -> String?
    var isKnownApp: (String) -> Bool

    func atRoot(_ path: String) -> URL { root.appendingPathComponent(path) }

    static var live: AppRoots {
        AppRoots(
            home: FileManager.default.homeDirectoryForCurrentUser,
            root: URL(fileURLWithPath: "/"),
            userCache: darwinDirectory(_CS_DARWIN_USER_CACHE_DIR),
            userTemp: darwinDirectory(_CS_DARWIN_USER_TEMP_DIR),
            caskrooms: AppNames.caskroomPaths.map { URL(fileURLWithPath: $0) },
            pkgutil: runPkgutil,
            isKnownApp: launchServicesKnows)
    }

    static func darwinDirectory(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    static func launchServicesKnows(_ bundleID: String) -> Bool {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] else { return false }
        return urls.contains { !AppInventory.isInTrash($0) && FileManager.default.fileExists(atPath: $0.path) }
    }

    static func runPkgutil(_ arguments: [String]) -> String? { run(AppNames.pkgutilPath, arguments) }

    static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return nil }
        let reader = DispatchGroup()
        var data = Data()
        reader.enter()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        guard reader.wait(timeout: .now() + 10) == .success, finished.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            return nil
        }
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

enum AppInventory {
    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    static func isRealDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    static func parallelMap<T, R>(_ items: [T], _ transform: (T) -> R?) -> [R] {
        var results = [R?](repeating: nil, count: items.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: items.count) { buffer[$0] = transform(items[$0]) }
        }
        return results.compactMap { $0 }
    }

    private static func bundles(in dir: URL, deep: Bool) -> [(url: URL, direct: Bool)] {
        let fm = FileManager.default
        var found: [(URL, Bool)] = []
        for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix(".") {
            let child = dir.appendingPathComponent(name)
            if name.lowercased().hasSuffix(".app") {
                found.append((child, true))
            } else if deep, isRealDirectory(child) {
                for inner in ((try? fm.contentsOfDirectory(atPath: child.path)) ?? []).sorted() where inner.lowercased().hasSuffix(".app") && !inner.hasPrefix(".") {
                    found.append((child.appendingPathComponent(inner), false))
                }
            }
        }
        return found
    }

    static func installed(_ roots: AppRoots) -> [AppIdentity] { scan(roots).installed }

    static func scan(_ roots: AppRoots) -> (installed: [AppIdentity], own: [AppIdentity]) {
        let systemPrefix = roots.root.resolvingSymlinksInPath().appendingPathComponent("System").path + "/"
        let candidates = [roots.atRoot("Applications"), roots.home.appendingPathComponent("Applications")].flatMap { bundles(in: $0, deep: true) }
        let found: [(AppIdentity, String)] = parallelMap(candidates) { candidate in
            let real = candidate.url.resolvingSymlinksInPath()
            guard !(real.path + "/").hasPrefix(systemPrefix), !isInTrash(real) else { return nil }
            guard let app = AppIdentity.read(at: candidate.url), !app.isPlatform else { return nil }
            if app.bundleID.lowercased().hasPrefix(AppNames.appleBundleIDPrefix) && !candidate.direct { return nil }
            return (app, real.path)
        }
        var seen = Set<String>()
        let apps = found.filter { seen.insert($0.1).inserted }.map { $0.0 }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return (apps.filter { !$0.isOwn }, apps.filter(\.isOwn))
    }

    static func system(_ roots: AppRoots) -> [AppIdentity] {
        let urls = AppNames.systemAppFolders.flatMap { bundles(in: roots.atRoot($0), deep: false).map { $0.url } }
        var seen = Set<String>()
        let apps: [AppIdentity] = parallelMap(urls) { AppIdentity.read(at: $0, signed: false) }
        return apps.filter { app in
            let inApplications = app.url.path.hasPrefix(roots.atRoot("Applications").path + "/")
            return (!inApplications || app.bundleID.lowercased().hasPrefix(AppNames.appleBundleIDPrefix)) && seen.insert(app.url.resolvingSymlinksInPath().path).inserted
        }
    }

    static func trashed(_ roots: AppRoots) -> [AppIdentity] {
        parallelMap(bundles(in: roots.home.appendingPathComponent(".Trash"), deep: false).map { $0.url }) { AppIdentity.read(at: $0) }
    }
}
