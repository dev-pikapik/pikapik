import Foundation

@main
struct TestPrivacyManifest {
    static let reasons: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1", "8FFB.1", "3D61.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
    ]

    static let calls: [String: String] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": #"\bUserDefaults\b|\bCFPreferences"#,
        "NSPrivacyAccessedAPICategorySystemBootTime": #"\bsystemUptime\b|\bmach_absolute_time\b|KERN_BOOTTIME"#,
        "NSPrivacyAccessedAPICategoryFileTimestamp": #"\b[lf]?stat\(|\bfstatat\(|\bgetattrlist\b|\bcreationDate\b|\bmodificationDate\b|contentModificationDate|\bst_[mac]timespec\b"#,
        "NSPrivacyAccessedAPICategoryDiskSpace": #"volumeAvailableCapacity|volumeTotalCapacity|\bsystemFreeSize\b|\bsystemSize\b|\bstatv?fs\("#,
    ]

    static func main() {
        guard let data = FileManager.default.contents(atPath: "Resources/PrivacyInfo.xcprivacy"),
              let manifest = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let types = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        else { preconditionFailure("Resources/PrivacyInfo.xcprivacy can't be read as a property list with NSPrivacyAccessedAPITypes") }
        var declared: Set<String> = []
        for entry in types {
            let category = entry["NSPrivacyAccessedAPIType"] as? String ?? ""
            let given = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            guard let allowed = reasons[category] else { preconditionFailure("\(category) is not a category this test knows; add it here with the reasons Apple lists for it") }
            precondition(!given.isEmpty && given.allSatisfy(allowed.contains), "\(category) gives \(given), but Apple accepts only \(allowed.sorted())")
            declared.insert(category)
        }
        print("every category in the privacy manifest gives reasons from Apple's list: ok")

        let files = ["Sources", "Extensions"].flatMap { root in
            (FileManager.default.enumerator(atPath: root)?.compactMap { $0 as? String } ?? []).filter { $0.hasSuffix(".swift") }.map { root + "/" + $0 }
        }.sorted()
        precondition(files.count > 50)
        let patterns = calls.compactMapValues { try? NSRegularExpression(pattern: $0) }
        precondition(patterns.count == calls.count)
        var missing: [String] = []
        for file in files {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for (category, pattern) in patterns.sorted(by: { $0.key < $1.key }) where !declared.contains(category) {
                    if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        missing.append("\(category): \(file):\(index + 1)")
                    }
                }
            }
        }
        precondition(missing.isEmpty, "Resources/PrivacyInfo.xcprivacy doesn't declare the category these lines need:\n" + missing.joined(separator: "\n"))
        print("every API the App Store build may call that needs a reason is declared (\(files.count) files): ok")
    }
}
