import Foundation

@main
enum TestGuideTables {
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func write(_ table: [String: Any], _ name: String, in folder: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
        try data.write(to: folder.appendingPathComponent("\(name).loctable"))
    }

    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pikapik-guide-tables-\(getpid())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plural: [String: Any] = ["NSStringLocalizedFormatKey": "%#@files@"]
        try write(["en": ["REDUCE_MOTION": "Reduce motion", "%d files": plural] as [String: Any], "ru": ["REDUCE_MOTION": "Уменьшить движение"], "de": ["REDUCE_MOTION": "Bewegung reduzieren"],
                   "fr": ["REDUCE_MOTION": "Réduire les animations"], "ja": ["REDUCE_MOTION": "視差効果を減らす"]], "Localizable", in: folder)
        try write(["en": ["CFBundleDisplayName": "Accessibility"], "ru": ["CFBundleDisplayName": "Универсальный доступ"], "de": ["CFBundleDisplayName": "Bedienungshilfen"]], "InfoPlist", in: folder)
        try write(["en": ["Other": "Other"], "ru": ["Other": "Другое"]], "A-Other", in: folder)

        let russian = GuideTables.load(folder, languages: ["ru-RU", "en"])
        check(russian.count == 3, "every table of the pane is read: \(russian.count)")
        check(Set(russian[0].keys) == ["en", "ru"], "only English and the language shown are kept: \(russian[0].keys.sorted())")
        check(russian[0]["ru"]?["REDUCE_MOTION"] == "Уменьшить движение", "the shown language keeps its strings")
        check(russian[0]["en"]?["REDUCE_MOTION"] == "Reduce motion", "English keeps its strings")
        check(russian[0]["en"]?["%d files"] == nil, "plural rules, which are not text, are left out")
        check(russian[1]["ru"]?["Other"] == "Другое", "Localizable comes first, the other tables follow by name")
        check(russian.allSatisfy { Set($0.keys).isSubset(of: ["en", "ru"]) }, "no table keeps a third language")

        let german = GuideTables.load(folder, only: "InfoPlist", languages: ["de-DE"])
        check(german.count == 1, "only the named table is read when one is named")
        check(Set(german[0].keys) == ["en", "de"], "German Macs keep English and German: \(german[0].keys.sorted())")
        check(GuideTables.language(of: Array(german[0].keys), languages: ["de-DE"]) == "de", "the kept tables still pick German")

        let missing = GuideTables.load(folder, only: "InfoPlist", languages: ["ko"])
        check(Set(missing[0].keys) == ["en"], "a language the pane does not have falls back to English alone: \(missing[0].keys.sorted())")
        check(GuideTables.load(folder.appendingPathComponent("absent"), languages: ["en"]).isEmpty, "a pane that is not there gives no tables")

        let system = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex/Contents/Resources")
        let files = ((try? FileManager.default.contentsOfDirectory(at: system, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "loctable" }
        if files.isEmpty {
            print("skipped: this Mac has no Accessibility settings tables")
        } else {
            let raw = files.compactMap { NSDictionary(contentsOf: $0) as? [String: Any] }
            let before = raw.reduce(0) { $0 + $1.values.reduce(0) { $0 + (($1 as? [String: Any])?.count ?? 0) } }
            let kept = GuideTables.load(system, languages: ["ru", "en"])
            let after = kept.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
            check(kept.allSatisfy { $0.count <= 2 }, "the Accessibility pane keeps at most two languages per table")
            check(after * 5 < before, "and far fewer strings: \(after) of \(before)")
            print("Accessibility pane: \(raw.map(\.count).max() ?? 0) languages and \(before) strings on disk, \(after) strings kept")
        }
        print("guide tables: ok")
    }
}
