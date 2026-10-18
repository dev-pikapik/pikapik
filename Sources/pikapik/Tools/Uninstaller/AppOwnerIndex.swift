import Foundation

struct Mode: OptionSet {
    let rawValue: Int
    static let id = Mode(rawValue: 1)
    static let name = Mode(rawValue: 2)
    static let vendor = Mode(rawValue: 4)
    static let group = Mode(rawValue: 8)
    static let executable = Mode(rawValue: 16)
    static let embedded = Mode(rawValue: 32)
    static let helper = Mode(rawValue: 64)
    static let soft = Mode(rawValue: 128)
    static let container = Mode(rawValue: 256)
    static let vendorChild = Mode(rawValue: 512)
    static let job = Mode(rawValue: 1024)
}

struct Place {
    enum Base { case home, root, userCache, userTemp }
    var base: Base
    var path: String
    var kind: LeftoverKind
    var mode: Mode

    init(_ base: Base, _ path: String, _ kind: LeftoverKind, _ mode: Mode) {
        self.base = base
        self.path = path
        self.kind = kind
        self.mode = mode
    }
}

struct Claim {
    var tier: Int
    var spec: Int
    var reason: LeftoverReason
    var loose = false

    var rank: Int { tier * 100_000 + spec }
}

struct Job {
    var url: URL
    var label: String
    var associated: [String]
    var program: String?
    var isDaemon: Bool
}

struct Cask {
    var token: String
    var dir: URL
    var appNames: [String] = []
    var packages: [String] = []
    var zap: [String] = []
    var staged: [String] = []
}

struct OwnerIndex {
    struct IDHit {
        var app: Int
        var id: String
        var loose: Bool
    }

    var apps: [AppIdentity]
    var byID: [String: [IDHit]] = [:]
    var byGroup: [String: [Int]] = [:]
    var byName: [String: [Int]] = [:]
    var byVendorless: [String: [Int]] = [:]
    var byVendor: [String: [Int]] = [:]
    var byTeam: [String: [Int]] = [:]
    var byExecutable: [String: [Int]] = [:]
    var byHelper: [String: [(app: Int, label: String)]] = [:]
    var appPaths: [(path: String, app: Int)] = []
    var allIDs: Set<String> = []
    var idPrefixes: Set<String> = []
    var vendorPrefixes: Set<String> = []

    init(_ apps: [AppIdentity], blocked: Set<String>) {
        self.apps = apps
        for (position, app) in apps.enumerated() {
            for id in app.strongIDs { byID[id.lowercased(), default: []].append(IDHit(app: position, id: id, loose: false)) }
            for id in app.looseIDs { byID[id.lowercased(), default: []].append(IDHit(app: position, id: id, loose: true)) }
            for id in app.ids.map({ $0.lowercased() }) {
                allIDs.insert(id)
                idPrefixes.formUnion(AppNames.dottedPrefixes(id))
                vendorPrefixes.insert(AppNames.twoParts(id))
            }
            for group in app.groups { byGroup[group.lowercased(), default: []].append(position) }
            let names = app.names.map(AppNames.squash)
            for key in Set(names) where AppNames.usable(key, blocked: blocked) { byName[key, default: []].append(position) }
            let vendors = app.vendors.map(AppNames.squash)
            for vendor in vendors {
                byVendor[vendor, default: []].append(position)
                for name in names where name.hasPrefix(vendor) && name.count - vendor.count >= 3 {
                    let rest = String(name.dropFirst(vendor.count))
                    if AppNames.usable(rest, blocked: blocked) { byVendorless[rest, default: []].append(position) }
                }
            }
            if !app.teamID.isEmpty { byTeam[app.teamID, default: []].append(position) }
            for executable in app.executables where AppNames.usable(AppNames.squash(executable), blocked: blocked) {
                byExecutable[executable.lowercased(), default: []].append(position)
            }
            for label in app.helperLabels { byHelper[label.lowercased(), default: []].append((position, label)) }
            appPaths.append((app.url.standardizedFileURL.path, position))
        }
    }

    func claims(_ entry: String, name: String? = nil, extraIDs: [String] = [], mode: Mode) -> [Int: Claim] {
        var found: [Int: Claim] = [:]
        func put(_ app: Int, _ claim: Claim) {
            if let existing = found[app], existing.rank >= claim.rank { return }
            found[app] = claim
        }
        if mode.contains(.id) {
            for form in ([entry] + extraIDs).flatMap(AppNames.idForms) {
                for prefix in AppNames.dottedPrefixes(form) {
                    for hit in byID[prefix] ?? [] { put(hit.app, Claim(tier: 3, spec: prefix.count, reason: .byID(hit.id), loose: hit.loose)) }
                }
            }
        }
        if mode.contains(.group) {
            let key = entry.lowercased()
            for app in byGroup[key] ?? [] { put(app, Claim(tier: 3, spec: key.count, reason: .appGroup(entry))) }
            if let team = entry.range(of: "^[A-Z0-9]{10}(?=\\.)", options: .regularExpression) {
                for app in byTeam[String(entry[team])] ?? [] { put(app, Claim(tier: 1, spec: 10, reason: .related)) }
            }
        }
        if mode.contains(.name) || mode.contains(.vendorChild) {
            let key = AppNames.squash(name ?? entry)
            if mode.contains(.name) {
                for app in byName[key] ?? [] { put(app, Claim(tier: mode.contains(.soft) ? 1 : 2, spec: key.count, reason: .byName)) }
                for prefix in AppNames.nameBoundaries(name ?? entry) {
                    for app in byName[prefix] ?? [] { put(app, Claim(tier: 1, spec: prefix.count, reason: .related)) }
                }
            }
            if mode.contains(.vendorChild) {
                for app in byVendorless[key] ?? [] { put(app, Claim(tier: 2, spec: key.count, reason: .vendor)) }
            }
        }
        if mode.contains(.executable), let process = AppNames.processName(entry)?.lowercased() {
            for app in byExecutable[process] ?? [] { put(app, Claim(tier: 3, spec: process.count, reason: .byName)) }
        }
        if mode.contains(.helper) {
            for hit in byHelper[entry.lowercased()] ?? [] { put(hit.app, Claim(tier: 3, spec: entry.count, reason: .helper(hit.label))) }
        }
        return found
    }

    func jobClaims(_ job: Job) -> [Int: Claim] {
        var found: [Int: Claim] = [:]
        func put(_ app: Int, _ claim: Claim) {
            if let existing = found[app], existing.rank >= claim.rank { return }
            found[app] = claim
        }
        let label = job.label.lowercased()
        for prefix in AppNames.dottedPrefixes(label) {
            for hit in byID[prefix] ?? [] { put(hit.app, Claim(tier: 3, spec: prefix.count, reason: .launchJob(job.label), loose: hit.loose)) }
        }
        for id in job.associated {
            for hit in byID[id.lowercased()] ?? [] { put(hit.app, Claim(tier: 3, spec: id.count, reason: .launchJob(job.label), loose: hit.loose)) }
        }
        for hit in byHelper[label] ?? [] { put(hit.app, Claim(tier: 3, spec: label.count, reason: .helper(hit.label))) }
        if let program = job.program {
            for entry in appPaths where program.hasPrefix(entry.path + "/") { put(entry.app, Claim(tier: 3, spec: 99_000, reason: .launchJob(job.label))) }
            if program.contains("/PrivilegedHelperTools/") {
                for hit in byHelper[URL(fileURLWithPath: program).lastPathComponent.lowercased()] ?? [] {
                    put(hit.app, Claim(tier: 3, spec: 98_000, reason: .helper(hit.label)))
                }
            }
        }
        return found
    }

    func knowsVendor(_ id: String) -> Bool {
        guard let word = id.split(separator: ".").dropFirst().first.map({ AppNames.squash(String($0)) }), AppNames.usable(word) else { return false }
        return byVendor[word] != nil || byName[word] != nil
    }

    func sharers(ofVendor vendor: String, team: String, excluding url: URL) -> [AppIdentity] {
        var positions = Set(byVendor[vendor] ?? [])
        if !team.isEmpty { positions.formUnion(byTeam[team] ?? []) }
        return positions.sorted().map { apps[$0] }.filter { $0.url != url }
    }
}

enum AppSearch {
    private static let cyrillic = Array("йцукенгшщзфывапролдячсмить")
    private static let latin = Array("qwertyuiopasdfghjklzxcvbnm")
    private static let toLatin: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(cyrillic, latin)).merging(["і": "s"]) { first, _ in first }
    private static let toRussian: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(latin, cyrillic))
    private static let toUkrainian: [Character: Character] = toRussian.merging(["s": "і"]) { _, new in new }

    private static func variants(_ query: String) -> [String] {
        let lower = query.lowercased()
        var found = [lower]
        for table in [toLatin, toRussian, toUkrainian] {
            let converted = String(lower.map { table[$0] ?? $0 })
            if !found.contains(converted) { found.append(converted) }
        }
        return found
    }

    private static func isWordPrefix(_ terms: [Substring], of text: String) -> Bool {
        let words = text.split(separator: " ")
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }

    private static func initials(_ text: String) -> String {
        String(text.split(separator: " ").compactMap(\.first))
    }

    static func score(_ query: String, titles: [String], others: [String]) -> Int {
        let names = titles.map(SettingsSearch.normalized)
        let rest = others.map(SettingsSearch.normalized)
        var best = 0
        for (position, variant) in variants(query).enumerated() {
            let value = SettingsSearch.normalized(variant)
            guard !value.isEmpty else { continue }
            let terms = value.split(separator: " ")
            var points = 0
            if names.contains(value) {
                points = 100
            } else if names.contains(where: { $0.hasPrefix(value) }) {
                points = 90
            } else if names.contains(where: { isWordPrefix(terms, of: $0) }) {
                points = 80
            } else if terms.count == 1, value.count >= 2, names.contains(where: { initials($0).hasPrefix(value) }) {
                points = 70
            } else if rest.contains(where: { isWordPrefix(terms, of: $0) }) {
                points = 60
            } else if SettingsSearch.matches(variant, fields: titles + others) {
                points = 50
            }
            if points > 0 { best = max(best, points - (position == 0 ? 0 : 5)) }
        }
        return best
    }

    static func score(_ app: AppIdentity, query: String) -> Int {
        score(query, titles: [app.displayName] + app.names, others: app.vendors + [app.organization, app.bundleID])
    }

    static func matches(_ app: AppIdentity, query: String) -> Bool {
        score(app, query: query) > 0
    }

    static func filter(_ apps: [AppIdentity], query: String) -> [AppIdentity] {
        guard !SettingsSearch.normalized(query).isEmpty else { return apps }
        let scored = apps.map { (app: $0, points: score($0, query: query)) }.filter { $0.points > 0 }
        return scored.sorted {
            $0.points != $1.points ? $0.points > $1.points : $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending
        }.map(\.app)
    }
}
