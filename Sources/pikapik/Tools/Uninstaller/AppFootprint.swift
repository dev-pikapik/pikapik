import AppKit
import Foundation

final class AppFootprint {
    let roots: AppRoots
    let installed: [AppIdentity]
    let system: [AppIdentity]
    let store: URL?
    fileprivate let blocked: Set<String>
    fileprivate let index: OwnerIndex
    fileprivate var listings: [String: [String]] = [:]
    fileprivate var bundleIDs: [String: String] = [:]
    fileprivate var containerIDs: [String: String] = [:]
    fileprivate lazy var places: [Place] = makePlaces()
    fileprivate lazy var kindByDirectory: [String: LeftoverKind] = Dictionary(
        places.map { (directory($0).standardizedFileURL.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
    fileprivate lazy var protectedPaths: Set<String> = makeProtectedPaths()
    fileprivate lazy var neverPrefixes: [String] = makeNeverPrefixes()
    fileprivate lazy var jobs: [Job] = loadJobs()
    fileprivate lazy var casks: [Cask] = loadCasks()
    fileprivate lazy var thirdPartyPackages: [String] = (roots.pkgutil(["--pkgs"]) ?? "").split(separator: "\n").map(String.init)
        .filter { !$0.lowercased().hasPrefix("com.apple.") }

    init(roots: AppRoots, installed: [AppIdentity], system: [AppIdentity] = [], own: [AppIdentity] = [], store: URL? = nil) {
        self.roots = roots
        self.installed = installed
        self.store = store
        let known = Set(installed.map { $0.url.path })
        let outside = system.filter { !known.contains($0.url.path) }
        self.system = outside
        blocked = Set(outside.flatMap { $0.names.map(AppNames.squash) })
        index = OwnerIndex(installed + outside + own, blocked: blocked)
    }

    static func putBackStore(home: URL, bundleID: String?) -> URL {
        let folder = AppConstants.appName + (bundleID?.hasSuffix(".dev") == true ? "-dev" : "")
        return home.appendingPathComponent("Library/Application Support/\(folder)/Uninstaller")
    }

    fileprivate static let userPlaces: [Place] = [
        Place(.home, "Library/Application Support", .appData, [.id, .name, .vendor]),
        Place(.home, "Library/Application Support/CrashReporter", .logs, [.executable]),
        Place(.home, "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments", .preferences, [.id]),
        Place(.home, "Library/Caches", .caches, [.id, .name, .vendor]),
        Place(.home, "Library/Preferences", .preferences, [.id]),
        Place(.home, "Library/Preferences/ByHost", .preferences, [.id]),
        Place(.home, "Library/SyncedPreferences", .preferences, [.id]),
        Place(.home, "Library/Containers", .containers, [.id, .container]),
        Place(.home, "Library/Group Containers", .containers, [.id, .group]),
        Place(.home, "Library/Application Scripts", .containers, [.id, .group]),
        Place(.home, "Library/Saved Application State", .preferences, [.id]),
        Place(.home, "Library/HTTPStorages", .caches, [.id]),
        Place(.home, "Library/WebKit", .caches, [.id]),
        Place(.home, "Library/Cookies", .caches, [.id]),
        Place(.home, "Library/Logs", .logs, [.id, .name, .vendor]),
        Place(.home, "Library/Logs/DiagnosticReports", .logs, [.executable]),
        Place(.home, "Library/LaunchAgents", .background, [.job]),
        Place(.home, "Library/Developer", .appData, [.name, .soft]),
    ]

    fileprivate static let extensionFolders = [
        "Library/Internet Plug-Ins", "Library/PreferencePanes", "Library/Services", "Library/QuickLook", "Library/Spotlight",
        "Library/Screen Savers", "Library/Input Methods", "Library/ColorPickers",
    ]

    fileprivate static let localPlaces: [Place] = [
        Place(.root, "Library/Application Support", .appData, [.id, .name, .vendor]),
        Place(.root, "Library/Caches", .caches, [.id, .name, .vendor]),
        Place(.root, "Library/Preferences", .preferences, [.id]),
        Place(.root, "Library/Logs/DiagnosticReports", .logs, [.executable]),
        Place(.root, "Library/LaunchAgents", .background, [.job]),
        Place(.root, "Library/LaunchDaemons", .background, [.job]),
        Place(.root, "Library/PrivilegedHelperTools", .background, [.id, .helper]),
        Place(.root, "Library/Extensions", .extensions, [.embedded, .name, .soft]),
        Place(.root, "Library/Frameworks", .extensions, [.embedded, .name, .soft]),
        Place(.root, "Users/Shared", .appData, [.id, .name, .soft]),
    ]

    fileprivate func directory(_ place: Place) -> URL {
        switch place.base {
        case .home: return roots.home.appendingPathComponent(place.path)
        case .root: return roots.atRoot(place.path)
        case .userCache: return roots.userCache ?? roots.atRoot("var/empty/cache")
        case .userTemp: return roots.userTemp ?? roots.atRoot("var/empty/temp")
        }
    }

    private func makePlaces() -> [Place] {
        var list = Self.userPlaces + Self.localPlaces
        let soft: Mode = [.embedded, .name, .soft]
        for folder in Self.extensionFolders {
            list.append(Place(.home, folder, .extensions, soft))
            if folder != "Library/Services", folder != "Library/ColorPickers" { list.append(Place(.root, folder, .extensions, soft)) }
        }
        for base in [Place.Base.home, .root] {
            let audio = Place(base, "Library/Audio/Plug-Ins", .extensions, soft)
            for name in listing(directory(audio)) where AppInventory.isRealDirectory(directory(audio).appendingPathComponent(name)) {
                list.append(Place(base, audio.path + "/" + name, .extensions, soft))
            }
        }
        if roots.userCache != nil { list.append(Place(.userCache, "", .caches, [.id])) }
        if roots.userTemp != nil { list.append(Place(.userTemp, "", .caches, [.id])) }
        return list
    }

    private func makeProtectedPaths() -> Set<String> {
        var paths: Set<String> = []
        var directories = places.map { directory($0) }
        directories += [roots.home.appendingPathComponent("Library/Audio/Plug-Ins"), roots.home, roots.root]
        directories += roots.caskrooms + AppFootprint.linkFolders(roots)
        if let store { directories.append(store) }
        for url in directories {
            var current = url.standardizedFileURL
            while paths.insert(current.path).inserted, current.path != "/" { current = current.deletingLastPathComponent() }
        }
        return paths
    }

    private func makeNeverPrefixes() -> [String] {
        let rootFolders = ["System", "usr", "bin", "sbin", "private/etc", "etc"].map { roots.atRoot($0).standardizedFileURL.path }
        let homeFolders = ["Library/Mobile Documents", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"]
            .map { roots.home.appendingPathComponent($0).standardizedFileURL.path }
        return rootFolders + homeFolders
    }

    fileprivate static func linkFolders(_ roots: AppRoots) -> [URL] {
        [roots.atRoot("usr/local/bin"), roots.atRoot("opt/homebrew/bin"), roots.home.appendingPathComponent(".local/bin"), roots.home.appendingPathComponent("bin")]
    }

    fileprivate func listing(_ dir: URL) -> [String] {
        if let cached = listings[dir.path] { return cached }
        var names: [String] = []
        if AppInventory.isRealDirectory(dir) {
            names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        }
        listings[dir.path] = names
        return names
    }

    func isProtected(_ url: URL, for app: AppIdentity, names: [String], allowLink: Bool = false) -> Bool {
        let path = url.standardizedFileURL.path
        if protectedPaths.contains(path) || url.pathComponents.contains("Keychains") { return true }
        let usrLocalBin = roots.atRoot("usr/local/bin").standardizedFileURL.path + "/"
        for prefix in neverPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            if allowLink, path.hasPrefix(usrLocalBin) { continue }
            return true
        }
        let forms = names.flatMap(AppNames.idForms)
        guard AppNames.isApple(forms) else { return false }
        let own = app.bundleID.lowercased()
        return !(own.hasPrefix("com.apple.") && forms.contains { $0 == own || $0.hasPrefix(own + ".") })
    }

    func fileInfo(_ url: URL) -> (device: Int32, inode: UInt64, isLink: Bool, isDirectory: Bool)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber, let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        let type = attributes[.type] as? FileAttributeType
        return (device.int32Value, inode.uint64Value, type == .typeSymbolicLink, type == .typeDirectory)
    }

    func needsAdmin(_ url: URL, isLink: Bool, isDirectory: Bool) -> Bool {
        func blocked(_ path: String) -> Bool {
            guard access(path, W_OK) != 0 else { return false }
            guard errno == EPERM else { return true }
            return ((try? FileManager.default.attributesOfItem(atPath: path))?[.ownerAccountID] as? NSNumber)?.uint32Value != getuid()
        }
        if blocked(url.deletingLastPathComponent().path) { return true }
        return !isLink && isDirectory && blocked(url.path)
    }

    fileprivate func embeddedID(_ url: URL) -> String? {
        if let cached = bundleIDs[url.path] { return cached.isEmpty ? nil : cached }
        var found = ""
        for path in ["Contents/Info.plist", "Resources/Info.plist", "Versions/Current/Resources/Info.plist", "Info.plist"] {
            if let info = NSDictionary(contentsOf: url.appendingPathComponent(path)) as? [String: Any], let id = info["CFBundleIdentifier"] as? String {
                found = id
                break
            }
        }
        bundleIDs[url.path] = found
        return found.isEmpty ? nil : found
    }

    fileprivate func containerID(_ url: URL) -> String? {
        if let cached = containerIDs[url.path] { return cached.isEmpty ? nil : cached }
        let info = NSDictionary(contentsOf: url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")) as? [String: Any]
        let found = info?["MCMMetadataIdentifier"] as? String ?? ""
        containerIDs[url.path] = found
        return found.isEmpty ? nil : found
    }

    fileprivate func isUUID(_ name: String) -> Bool {
        name.range(of: "^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$", options: .regularExpression) != nil
    }

    fileprivate func loadJobs() -> [Job] {
        let folders = [(roots.home.appendingPathComponent("Library/LaunchAgents"), false), (roots.atRoot("Library/LaunchAgents"), false), (roots.atRoot("Library/LaunchDaemons"), true)]
        var list: [Job] = []
        for (dir, daemon) in folders {
            for name in listing(dir) where name.hasSuffix(".plist") {
                let url = dir.appendingPathComponent(name)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                guard size < 1_000_000 else { continue }
                let info = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
                let associated = info["AssociatedBundleIdentifiers"] as? [String] ?? (info["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
                let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
                list.append(Job(url: url, label: info["Label"] as? String ?? String(name.dropLast(6)), associated: associated, program: program, isDaemon: daemon))
            }
        }
        return list
    }

    private func artifactValues(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    fileprivate func loadCasks() -> [Cask] {
        let fm = FileManager.default
        var list: [Cask] = []
        for caskroom in roots.caskrooms {
            for token in listing(caskroom) {
                let dir = caskroom.appendingPathComponent(token)
                guard AppInventory.isRealDirectory(dir) else { continue }
                let meta = dir.appendingPathComponent(".metadata")
                var files = [meta.appendingPathComponent("INSTALL_RECEIPT.json")]
                for version in (try? fm.contentsOfDirectory(atPath: meta.path)) ?? [] {
                    for stamp in (try? fm.contentsOfDirectory(atPath: meta.appendingPathComponent(version).path)) ?? [] {
                        files.append(meta.appendingPathComponent("\(version)/\(stamp)/Casks/\(token).json"))
                    }
                }
                var cask = Cask(token: token, dir: dir)
                for file in files {
                    guard let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let artifacts = (json["uninstall_artifacts"] as? [[String: Any]] ?? []) + (json["artifacts"] as? [[String: Any]] ?? [])
                    for artifact in artifacts {
                        for entry in artifact["app"] as? [Any] ?? [] {
                            if let name = entry as? String { cask.appNames.append(URL(fileURLWithPath: name).lastPathComponent) }
                            if let target = (entry as? [String: Any])?["target"] as? String { cask.appNames.append(URL(fileURLWithPath: target).lastPathComponent) }
                        }
                        for step in artifact["uninstall"] as? [[String: Any]] ?? [] { cask.packages += artifactValues(step["pkgutil"]) }
                        for step in artifact["zap"] as? [[String: Any]] ?? [] {
                            for key in ["trash", "delete"] { cask.zap += artifactValues(step[key]) }
                        }
                    }
                }
                for version in listing(dir) where AppInventory.isRealDirectory(dir.appendingPathComponent(version)) {
                    for name in listing(dir.appendingPathComponent(version)) where name.lowercased().hasSuffix(".app") {
                        cask.staged.append(dir.appendingPathComponent(version).appendingPathComponent(name).path)
                    }
                }
                list.append(cask)
            }
        }
        return list
    }

    fileprivate func isInstalledElsewhere(_ app: AppIdentity) -> Bool {
        guard !app.bundleID.isEmpty else { return false }
        return installed.contains { $0.url != app.url && $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame } || roots.isKnownApp(app.bundleID)
    }

    func trashed() -> [AppIdentity] {
        AppInventory.trashed(roots).filter { !isInstalledElsewhere($0) }
    }

    static var onEntry: (() -> Void)?

    static func allocatedSize(of url: URL) -> Int64 {
        guard let path = strdup(url.path) else { return 0 }
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return 0 }
        defer { fts_close(stream) }
        var total: Int64 = 0
        var linked = Set<UInt64>()
        var visited = 0
        while let entry = fts_read(stream) {
            onEntry?()
            visited += 1
            if visited % 1000 == 0, Task.isCancelled { break }
            let kind = Int32(entry.pointee.fts_info)
            guard [FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_DNR].contains(kind), let info = entry.pointee.fts_statp?.pointee else { continue }
            if kind != FTS_D, kind != FTS_DNR, info.st_nlink > 1, !linked.insert(info.st_ino).inserted { continue }
            total += Int64(info.st_blocks) * 512
        }
        return total
    }
}

private final class Run {
    let app: AppIdentity
    let owners: OwnerIndex
    let me: Int
    var found: [String: Leftover] = [:]

    init(app: AppIdentity, owners: OwnerIndex, me: Int) {
        self.app = app
        self.owners = owners
        self.me = me
    }

    func verdict(_ claims: [Int: Claim]) -> (claim: Claim, shared: [String])? {
        guard let mine = claims[me] else { return nil }
        var shared = Set<String>()
        for (other, claim) in claims where other != me {
            if claim.rank > mine.rank { return nil }
            if claim.rank == mine.rank { shared.insert(owners.apps[other].displayName) }
        }
        return (mine, shared.sorted())
    }

    func isForeign(_ claims: [Int: Claim]) -> Bool {
        claims.contains { $0.key != me && $0.value.tier >= 2 }
    }

    func siblings(named names: [String] = []) -> [AppIdentity] {
        var seen = Set<URL>()
        let keys = Set((app.vendors + names).map(AppNames.squash) + [""])
        return keys.sorted().flatMap { owners.sharers(ofVendor: $0, team: app.teamID, excluding: app.url) }.filter { seen.insert($0.url).inserted }
    }
}

extension AppFootprint {
    fileprivate static let orphanPaths: Set<String> = [
        "Library/Preferences", "Library/Preferences/ByHost", "Library/Containers", "Library/Group Containers", "Library/Saved Application State",
        "Library/Caches", "Library/HTTPStorages", "Library/WebKit", "Library/Application Support", "Library/Application Scripts", "Library/LaunchAgents",
    ]
    fileprivate static let orphanWalkLimit = 2000
    fileprivate static let orphanQuietPeriod: TimeInterval = 7 * 86_400

    convenience init(roots: AppRoots = .live, running: AppIdentity? = AppIdentity.read(at: Bundle.main.bundleURL)) {
        let apps = AppInventory.scan(roots)
        var own = apps.own
        if let running, !own.contains(where: { $0.url.resolvingSymlinksInPath() == running.url.resolvingSymlinksInPath() }) { own.append(running) }
        self.init(roots: roots, installed: apps.installed, system: AppInventory.system(roots), own: own,
                  store: running.map { AppFootprint.putBackStore(home: roots.home, bundleID: $0.bundleID) })
    }

    func isSystem(_ app: AppIdentity) -> Bool {
        let real = app.url.resolvingSymlinksInPath().path
        let prefix = roots.root.resolvingSymlinksInPath().appendingPathComponent("System").path + "/"
        return (real + "/").hasPrefix(prefix) || system.contains { $0.url.resolvingSymlinksInPath().path == real }
    }

    func scan(_ app: AppIdentity) -> [Leftover] {
        let run = makeRun(app)
        merge(makeLeftover(app.url, kind: .app, reason: .bundle, preselected: true), into: run)
        guard !Task.isCancelled else { return [] }
        scanPlaces(run)
        guard !Task.isCancelled else { return [] }
        scanJobs(run)
        guard !Task.isCancelled else { return [] }
        scanLinks(run)
        guard !Task.isCancelled else { return [] }
        let installer = installerPackages(app)
        guard !Task.isCancelled else { return [] }
        scanCasks(run, packages: installer.found)
        guard !Task.isCancelled else { return [] }
        scanReceipts(run, installer)
        return run.found.values.sorted { ($0.kind, $0.url.path.lowercased()) < ($1.kind, $1.url.path.lowercased()) }
    }

    fileprivate func makeRun(_ app: AppIdentity) -> Run {
        if let position = index.apps.firstIndex(where: { $0.url == app.url }) { return Run(app: app, owners: index, me: position) }
        return Run(app: app, owners: OwnerIndex(index.apps + [app], blocked: blocked), me: index.apps.count)
    }

    fileprivate func makeLeftover(_ url: URL, kind: LeftoverKind, reason: LeftoverReason, preselected: Bool, shared: [String] = []) -> Leftover? {
        guard let info = fileInfo(url) else { return nil }
        var item = Leftover(url: url, kind: kind, reason: reason, preselected: preselected && shared.isEmpty, sharedWith: shared)
        item.device = info.device
        item.inode = info.inode
        item.isLink = info.isLink
        item.needsAdmin = needsAdmin(url, isLink: info.isLink, isDirectory: info.isDirectory)
        return item
    }

    fileprivate static func strength(_ reason: LeftoverReason) -> Int {
        switch reason {
        case .bundle: return 9
        case .byID, .appGroup, .launchJob, .helper, .receipt, .cliLink, .homebrew: return 8
        case .vendor: return 4
        case .byName: return 3
        case .related: return 1
        }
    }

    fileprivate func merge(_ item: Leftover?, into run: Run) {
        guard let item else { return }
        let key = item.url.standardizedFileURL.path
        guard let existing = run.found[key] else {
            run.found[key] = item
            return
        }
        let incomingWins = Self.strength(item.reason) > Self.strength(existing.reason)
        var winner = incomingWins ? item : existing
        let loser = incomingWins ? existing : item
        winner.jobLabel = winner.jobLabel ?? loser.jobLabel
        winner.isDaemon = winner.isDaemon || loser.isDaemon
        winner.packageID = winner.packageID ?? loser.packageID
        run.found[key] = winner
    }

    fileprivate func preselects(_ claim: Claim, _ app: AppIdentity) -> Bool {
        guard !claim.loose else { return false }
        return claim.tier == 3 || (claim.tier == 2 && !app.bundleID.isEmpty)
    }

    fileprivate func propose(_ run: Run, _ url: URL, kind: LeftoverKind, claims: [Int: Claim], names: [String]) {
        guard let (claim, shared) = run.verdict(claims), !isProtected(url, for: run.app, names: names) else { return }
        merge(makeLeftover(url, kind: kind, reason: claim.reason, preselected: preselects(claim, run.app), shared: shared), into: run)
    }

    fileprivate func matchName(_ url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty, ext.count <= 12, ext.allSatisfy(\.isLetter) else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }

    fileprivate func scanPlaces(_ run: Run) {
        let vendorKeys = Set(run.app.vendors.map(AppNames.squash))
        for place in places where !place.mode.contains(.job) {
            let dir = directory(place)
            for name in listing(dir) {
                let url = dir.appendingPathComponent(name)
                var mode = place.mode
                var extra: [String] = []
                var title = name
                if mode.contains(.container), isUUID(name) {
                    guard let id = containerID(url) else { continue }
                    extra = [id]
                } else if mode.contains(.embedded) {
                    title = matchName(url)
                    if let id = embeddedID(url) {
                        extra = [id]
                        mode.insert(.id)
                    }
                }
                let claims = run.owners.claims(name, name: title, extraIDs: extra, mode: mode)
                if claims.isEmpty {
                    if mode.contains(.vendor), vendorKeys.contains(AppNames.squash(name)) { scanVendorFolder(run, url, kind: place.kind) }
                    continue
                }
                propose(run, url, kind: place.kind, claims: claims, names: [name] + extra)
            }
        }
    }

    fileprivate func scanVendorFolder(_ run: Run, _ url: URL, kind: LeftoverKind) {
        guard !isProtected(url, for: run.app, names: [url.lastPathComponent]) else { return }
        let alone = run.owners.sharers(ofVendor: AppNames.squash(url.lastPathComponent), team: run.app.teamID, excluding: run.app.url).isEmpty
        let children = listing(url).map { (name: $0, claims: run.owners.claims($0, mode: [.id, .name, .vendorChild])) }
        let ownsAll = alone && children.allSatisfy { child in
            guard let (claim, shared) = run.verdict(child.claims) else { return false }
            return shared.isEmpty && preselects(claim, run.app)
        }
        if ownsAll {
            merge(makeLeftover(url, kind: kind, reason: .vendor, preselected: true), into: run)
            return
        }
        for child in children {
            let claims = alone && child.claims.isEmpty ? [run.me: Claim(tier: 1, spec: 0, reason: .related)] : child.claims
            propose(run, url.appendingPathComponent(child.name), kind: kind, claims: claims, names: [child.name])
        }
    }

    fileprivate func scanJobs(_ run: Run) {
        let tools = roots.atRoot("Library/PrivilegedHelperTools").standardizedFileURL.path + "/"
        let owned = run.found.values.filter { $0.kind == .appData && $0.preselected && !$0.isLink }.map { $0.url.standardizedFileURL.path + "/" }
        for job in jobs {
            var claims = run.owners.jobClaims(job)
            for (app, claim) in run.owners.claims(job.url.lastPathComponent, mode: .id) where (claims[app]?.rank ?? 0) < claim.rank { claims[app] = claim }
            if claims[run.me] == nil, let program = job.program, owned.contains(where: { program.hasPrefix($0) }) {
                claims[run.me] = Claim(tier: 3, spec: 97_000, reason: .launchJob(job.label))
            }
            guard let (claim, shared) = run.verdict(claims), !isProtected(job.url, for: run.app, names: [job.url.lastPathComponent, job.label]) else { continue }
            let selected = preselects(claim, run.app)
            var item = makeLeftover(job.url, kind: .background, reason: claim.reason, preselected: selected, shared: shared)
            item?.jobLabel = job.label
            item?.isDaemon = job.isDaemon
            merge(item, into: run)
            var tool = [roots.atRoot("Library/PrivilegedHelperTools/" + job.label)]
            if let program = job.program, program.hasPrefix(tools) { tool.append(URL(fileURLWithPath: program)) }
            for url in tool where !isProtected(url, for: run.app, names: [url.lastPathComponent]) {
                merge(makeLeftover(url, kind: .background, reason: .helper(job.label), preselected: selected, shared: shared), into: run)
            }
        }
    }

    fileprivate func scanLinks(_ run: Run) {
        let bundle = run.app.url.resolvingSymlinksInPath().path + "/"
        for folder in Self.linkFolders(roots) {
            for name in listing(folder) {
                let url = folder.appendingPathComponent(name)
                guard let info = fileInfo(url), info.isLink, let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { continue }
                let destination = target.hasPrefix("/") ? URL(fileURLWithPath: target) : folder.appendingPathComponent(target)
                guard destination.resolvingSymlinksInPath().path.hasPrefix(bundle), !isProtected(url, for: run.app, names: [name], allowLink: true) else { continue }
                merge(makeLeftover(url, kind: .install, reason: .cliLink, preselected: true), into: run)
            }
        }
    }

    fileprivate func caskMatches(_ cask: Cask, _ app: AppIdentity, packages: [String] = []) -> Bool {
        let file = app.url.lastPathComponent.lowercased()
        if cask.appNames.contains(where: { $0.lowercased() == file }) || cask.packages.contains(where: packages.contains) { return true }
        let resolved = app.url.resolvingSymlinksInPath().path
        return cask.staged.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }
    }

    fileprivate func globbed(_ pattern: String) -> [String] {
        var results = glob_t()
        defer { globfree(&results) }
        guard glob(pattern, GLOB_NOSORT, nil, &results) == 0 else { return [] }
        return (0..<Int(results.gl_pathc)).compactMap { results.gl_pathv[$0].map { String(cString: $0) } }
    }

    fileprivate func zapPaths(_ cask: Cask) -> [URL] {
        let homeLibrary = roots.home.appendingPathComponent("Library").standardizedFileURL.path + "/"
        let rootLibrary = roots.atRoot("Library").standardizedFileURL.path + "/"
        var found: [URL] = []
        for raw in cask.zap {
            let expanded: String
            if raw.hasPrefix("~/") {
                expanded = roots.home.path + "/" + String(raw.dropFirst(2))
            } else if raw.hasPrefix("/Library/") {
                expanded = roots.atRoot(String(raw.dropFirst())).path
            } else {
                continue
            }
            var candidates = [expanded]
            if expanded.contains(where: { "*?[".contains($0) }) {
                guard expanded.hasPrefix(homeLibrary) else { continue }
                candidates = globbed(expanded)
            }
            for path in candidates {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                if url.path.hasPrefix(homeLibrary) || url.path.hasPrefix(rootLibrary) { found.append(url) }
            }
        }
        return found
    }

    fileprivate func scanCasks(_ run: Run, packages: [String]) {
        let matched = casks.filter { caskMatches($0, run.app, packages: packages) }
        let siblings = matched.contains { !$0.packages.isEmpty } ? run.siblings().map { (app: $0, packages: self.packages(at: $0.url)) } : []
        let vendorKeys = Set(run.app.vendors.map(AppNames.squash))
        for cask in matched {
            let users = run.owners.apps.filter { $0.url != run.app.url && caskMatches(cask, $0) } + siblings.filter { caskMatches(cask, $0.app, packages: $0.packages) }.map(\.app)
            let shared = Set(users.map(\.displayName)).sorted()
            merge(makeLeftover(cask.dir, kind: .install, reason: .homebrew(cask.token), preselected: true, shared: shared), into: run)
            for url in zapPaths(cask) {
                let name = url.lastPathComponent
                let kind = kindByDirectory[url.deletingLastPathComponent().standardizedFileURL.path] ?? .appData
                let inVendor = vendorKeys.contains(AppNames.squash(url.deletingLastPathComponent().lastPathComponent))
                let claims = run.owners.claims(name, mode: inVendor ? [.id, .name, .vendorChild] : [.id, .name])
                if claims.isEmpty, vendorKeys.contains(AppNames.squash(name)) {
                    scanVendorFolder(run, url, kind: kind)
                    continue
                }
                guard !run.isForeign(claims), !isProtected(url, for: run.app, names: [name]) else { continue }
                let verdict = run.verdict(claims)
                let selected = (verdict.map { preselects($0.claim, run.app) } ?? false) || run.found[url.standardizedFileURL.path]?.preselected == true
                merge(makeLeftover(url, kind: kind, reason: .homebrew(cask.token), preselected: selected, shared: Set(shared + (verdict?.shared ?? [])).sorted()), into: run)
            }
        }
    }

    fileprivate static func field(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix(key + ":") {
            return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func receiptPrefix(_ info: String) -> String {
        let location = (field("location", in: info) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return location.isEmpty ? "" : location + "/"
    }

    fileprivate func receiptCandidates(for app: AppIdentity) -> [String] {
        let vendors = Set(app.ids.map(AppNames.twoParts))
        let names = app.names.map(AppNames.squash).filter { $0.count >= 5 && AppNames.usable($0) }
        let related = thirdPartyPackages.filter { package in
            vendors.contains(AppNames.twoParts(package)) || names.contains { AppNames.squash(package).contains($0) }
        }
        return Array(related.prefix(8))
    }

    fileprivate func packages(at url: URL) -> [String] {
        AppIdentity.unique((roots.pkgutil(["--file-info", url.path]) ?? "").split(separator: "\n").compactMap { line in
            line.hasPrefix("pkgid:") ? String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) : nil
        })
    }

    fileprivate func installerPackages(_ app: AppIdentity) -> (found: [String], loaded: [String: (info: String, files: String)]) {
        var loaded: [String: (info: String, files: String)] = [:]
        var found = packages(at: app.url)
        if found.isEmpty {
            let appPath = app.url.standardizedFileURL.path
            for package in receiptCandidates(for: app) {
                let info = roots.pkgutil(["--pkg-info", package]) ?? ""
                let prefix = Self.receiptPrefix(info)
                guard let files = roots.pkgutil(["--files", package]), files.split(separator: "\n").contains(where: {
                    $0.hasSuffix(".app") && roots.atRoot(prefix + String($0)).standardizedFileURL.path == appPath
                }) else { continue }
                loaded[package] = (info, files)
                found.append(package)
            }
        }
        return (found, loaded)
    }

    fileprivate func scanReceipts(_ run: Run, _ installer: (found: [String], loaded: [String: (info: String, files: String)])) {
        let own = Set(installer.found)
        func listers(_ url: URL) -> [String] {
            packages(at: url).filter { !own.contains($0) }.flatMap { package -> [String] in
                let apps = run.owners.claims(package, mode: .id).keys.filter { $0 != run.me }.map { run.owners.apps[$0].displayName }
                return apps.isEmpty ? [AppNames.orphanTitle(package)] : apps
            }
        }
        func untick(_ url: URL, _ shared: [String]) {
            let key = url.standardizedFileURL.path
            guard !shared.isEmpty, var kept = run.found[key] else { return }
            kept.preselected = false
            kept.sharedWith = Set(kept.sharedWith + shared).sorted()
            run.found[key] = kept
        }
        for package in installer.found where !package.lowercased().hasPrefix("com.apple.") {
            let info = installer.loaded[package]?.info ?? roots.pkgutil(["--pkg-info", package]) ?? ""
            guard (Self.field("volume", in: info) ?? "/") == "/", let files = installer.loaded[package]?.files ?? roots.pkgutil(["--files", package]) else { continue }
            let prefix = Self.receiptPrefix(info)
            var otherApps = Set<String>()
            var listed: [String: Set<String>] = [:]
            var tops: [(url: URL, kind: LeftoverKind)] = []
            for line in files.split(separator: "\n") {
                let url = roots.atRoot(prefix + String(line))
                let parent = url.deletingLastPathComponent().standardizedFileURL.path
                if line.hasSuffix(".app"), let other = run.owners.appPaths.first(where: { $0.path == url.standardizedFileURL.path && $0.app != run.me }) {
                    otherApps.insert(run.owners.apps[other.app].displayName)
                }
                listed[parent, default: []].insert(url.lastPathComponent)
                if let kind = kindByDirectory[parent] { tops.append((url, kind)) }
            }
            var picks: [(url: URL, kind: LeftoverKind, selected: Bool, shared: [String])] = []
            for (url, kind) in tops {
                let name = url.lastPathComponent
                let id = embeddedID(url)
                let claims = run.owners.claims(name, name: id == nil ? name : matchName(url), extraIDs: id.map { [$0] } ?? [], mode: [.id, .name])
                guard let file = fileInfo(url), !run.isForeign(claims), !isProtected(url, for: run.app, names: [name] + (id.map { [$0] } ?? [])) else { continue }
                let verdict = run.verdict(claims)
                if !file.isDirectory || verdict.map({ preselects($0.claim, run.app) }) == true {
                    picks.append((url, kind, true, (verdict?.shared ?? []) + listers(url)))
                    continue
                }
                let contents = listed[url.standardizedFileURL.path] ?? []
                let others = listers(url)
                let siblings = run.siblings(named: [name])
                if others.isEmpty, id != nil || listing(url).allSatisfy(contents.contains), siblings.isEmpty {
                    picks.append((url, kind, true, []))
                } else if id != nil {
                    picks.append((url, kind, false, others))
                } else {
                    untick(url, otherApps.union(others).sorted())
                    for child in contents.sorted() {
                        let inner = url.appendingPathComponent(child)
                        let claims = run.owners.claims(child, mode: [.id, .name, .vendorChild])
                        guard fileInfo(inner) != nil, !run.isForeign(claims), !isProtected(inner, for: run.app, names: [child]) else { continue }
                        picks.append((inner, kind, siblings.isEmpty || run.verdict(claims).map { preselects($0.claim, run.app) } == true, listers(inner)))
                    }
                }
            }
            for pick in picks {
                let shared = otherApps.union(pick.shared).sorted()
                merge(makeLeftover(pick.url, kind: pick.kind, reason: .receipt(package), preselected: pick.selected, shared: shared), into: run)
                untick(pick.url, shared)
            }
            let shared = otherApps.sorted()
            var receipt = Leftover(url: roots.atRoot("var/db/receipts/\(package).plist"), kind: .install, reason: .receipt(package), preselected: shared.isEmpty, sharedWith: shared, needsAdmin: true)
            receipt.packageID = package
            merge(receipt, into: run)
        }
    }

    fileprivate func newestChange(of urls: [URL]) -> Date? {
        var newest = 0.0
        var visited = 0
        for url in urls {
            guard let path = strdup(url.path) else { return nil }
            defer { free(path) }
            var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
            guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
            defer { fts_close(stream) }
            while let entry = fts_read(stream) {
                let kind = Int32(entry.pointee.fts_info)
                if kind == FTS_DNR || kind == FTS_ERR || kind == FTS_NS { return nil }
                guard kind != FTS_DP, let info = entry.pointee.fts_statp?.pointee else { continue }
                newest = max(newest, Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
                visited += 1
                if visited % 1000 == 0, Task.isCancelled { return nil }
                if visited >= Self.orphanWalkLimit { break }
            }
        }
        return Date(timeIntervalSince1970: newest)
    }

    fileprivate func aliveJobs() -> (ids: Set<String>, programs: [String]) {
        var ids = Set<String>()
        var programs: [String] = []
        for job in jobs {
            guard let program = job.program, program.hasPrefix("/"), FileManager.default.fileExists(atPath: program), !AppInventory.isInTrash(URL(fileURLWithPath: program)) else { continue }
            ids.insert(job.label.lowercased())
            ids.formUnion(job.associated.map { $0.lowercased() })
            programs.append(program)
        }
        return (ids, programs)
    }

    func orphans(now: Date = Date()) -> [OrphanGroup] {
        struct Member {
            var url: URL
            var kind: LeftoverKind
            var raw: String
        }
        var families: [String: (id: String, members: [Member])] = [:]
        for place in places where place.base == .home && Self.orphanPaths.contains(place.path) {
            let dir = directory(place)
            for name in listing(dir) {
                guard let id = AppNames.orphanID(name) else { continue }
                families[id.lowercased(), default: (id, [])].members.append(Member(url: dir.appendingPathComponent(name), kind: place.kind, raw: name))
            }
        }
        var merged: [String: (id: String, members: [Member])] = [:]
        for key in families.keys.sorted(by: { $0.count < $1.count }) {
            guard let family = families[key] else { continue }
            if let root = AppNames.dottedPrefixes(key).reversed().first(where: { merged[$0] != nil }) {
                merged[root]?.members += family.members
            } else {
                merged[key] = family
            }
        }
        let alive = aliveJobs()
        var result: [OrphanGroup] = []
        for (key, family) in merged {
            if Task.isCancelled { return [] }
            guard !AppNames.isApple(family.members.flatMap { AppNames.idForms($0.raw) } + [key]) else { continue }
            guard index.claims(key, mode: .id).isEmpty, !index.idPrefixes.contains(key), !index.vendorPrefixes.contains(AppNames.twoParts(key)), !index.knowsVendor(key) else { continue }
            guard !AppNames.dottedPrefixes(key).contains(where: alive.ids.contains), !alive.ids.contains(where: { $0.hasPrefix(key + ".") }) else { continue }
            guard !family.members.contains(where: { member in alive.programs.contains { $0.hasPrefix(member.url.path + "/") } }) else { continue }
            guard !roots.isKnownApp(family.id) else { continue }
            guard let newest = newestChange(of: family.members.map(\.url)), now.timeIntervalSince(newest) >= Self.orphanQuietPeriod else { continue }
            let items = family.members.compactMap { makeLeftover($0.url, kind: $0.kind, reason: .byID(family.id), preselected: false) }
                .sorted { ($0.kind, $0.url.path.lowercased()) < ($1.kind, $1.url.path.lowercased()) }
            if !items.isEmpty { result.append(OrphanGroup(id: key, name: AppNames.orphanTitle(family.id), items: items, newest: newest)) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct LaunchTask {
    var url: URL
    var label: String
    var program: String?
    var isDaemon: Bool
    var owner: AppIdentity?
}

extension AppFootprint {
    func launchTasks() -> [LaunchTask] {
        jobs.filter { !AppNames.isApple([$0.label.lowercased()]) }.map { job in
            var claims = index.jobClaims(job)
            for (app, claim) in index.claims(job.url.lastPathComponent, mode: .id) where (claims[app]?.rank ?? 0) < claim.rank { claims[app] = claim }
            let best = claims.max { ($0.value.loose ? 0 : 1, $0.value.rank, -$0.key) < ($1.value.loose ? 0 : 1, $1.value.rank, -$1.key) }
            return LaunchTask(url: job.url, label: job.label, program: job.program, isDaemon: job.isDaemon, owner: best.map { index.apps[$0.key] })
        }
    }
}
