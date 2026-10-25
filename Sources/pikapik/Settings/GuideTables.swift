import Foundation

enum GuideTables {
    static func load(_ folder: URL, only name: String? = nil, languages: [String]) -> [[String: [String: String]]] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "loctable" }
        let wanted = files.filter { name == nil ? true : $0.deletingPathExtension().lastPathComponent == name }
        let ordered = wanted.filter { $0.lastPathComponent == "Localizable.loctable" } + wanted.filter { $0.lastPathComponent != "Localizable.loctable" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return ordered.compactMap { NSDictionary(contentsOf: $0) as? [String: Any] }.map { slim($0, languages: languages) }
    }

    static func slim(_ raw: [String: Any], languages: [String]) -> [String: [String: String]] {
        let shown = language(of: Array(raw.keys), languages: languages)
        return raw.filter { $0.key == "en" || $0.key == shown }.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
    }

    static func language(of keys: [String], languages: [String]) -> String {
        Bundle.preferredLocalizations(from: keys, forPreferences: languages).first ?? "en"
    }
}
