import AppKit

@main
struct TestSymbols {
    static let catalog = "Sources/pikapik/Core/Symbol.swift"
    static let drawers = ["Sources/pikapik/UI/SymbolViews.swift", "Sources/pikapik/UI/SymbolImage.swift"]

    /// "sun.max.fill" is `sunMaxFill`, and a name that starts with a digit gets "number" in front.
    static func caseName(_ name: String) -> String {
        let parts = name.split(separator: ".").map(String.init)
        let joined = parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return joined.first?.isNumber == true ? "number" + joined : joined
    }

    static func main() {
        precondition(caseName("sun.max.fill") == "sunMaxFill" && caseName("speaker.wave.2.fill") == "speakerWave2Fill" && caseName("7.square.fill") == "number7SquareFill")

        let all = Symbol.allCases
        precondition(all.count > 100)
        var problems: [String] = []

        let os = ProcessInfo.processInfo.operatingSystemVersion
        for symbol in all where NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil) == nil {
            problems.append("\"\(symbol.rawValue)\" is not a symbol on macOS \(os.majorVersion).\(os.minorVersion)")
        }
        precondition(problems.isEmpty, problems.joined(separator: "\n"))
        print("all \(all.count) symbols in the catalog exist on this Mac: ok")

        // The runner has a newer macOS than pikapik needs, so a symbol found above can still be missing on the oldest supported one
        let minimum = NSDictionary(contentsOfFile: "Sources/pikapik/Info.plist")?["LSMinimumSystemVersion"] as? String
        let table = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
        let availability = NSDictionary(contentsOfFile: table)
        guard let minimum, let years = availability?["symbols"] as? [String: String], let releases = availability?["year_to_release"] as? [String: [String: String]] else {
            preconditionFailure("needs LSMinimumSystemVersion in Sources/pikapik/Info.plist and the symbol availability table at \(table)")
        }
        for symbol in all {
            guard let year = years[symbol.rawValue], let mac = releases[year]?["macOS"] else {
                problems.append("\"\(symbol.rawValue)\" has no first macOS in \(table)")
                continue
            }
            if mac.compare(minimum, options: .numeric) == .orderedDescending {
                problems.append("\"\(symbol.rawValue)\" needs macOS \(mac), but pikapik runs on macOS \(minimum)")
            }
        }
        precondition(problems.isEmpty, problems.joined(separator: "\n"))
        print("every symbol is there on macOS \(minimum): ok")

        for (a, b) in zip(all, all.dropFirst()) where a.rawValue >= b.rawValue {
            problems.append("\"\(b.rawValue)\" goes before \"\(a.rawValue)\"")
        }
        for symbol in all where String(describing: symbol) != caseName(symbol.rawValue) {
            problems.append("\(symbol) should be named \(caseName(symbol.rawValue))")
        }
        precondition(problems.isEmpty, "\(catalog):\n" + problems.joined(separator: "\n"))
        print("the catalog is sorted and every case is named after its symbol: ok")

        var files: [String: String] = [:]
        for root in ["Sources", "Helper", "Extensions"] {
            for path in FileManager.default.enumerator(atPath: root)?.compactMap({ $0 as? String }) ?? [] where path.hasSuffix(".swift") {
                let file = root + "/" + path
                if file != catalog, let text = try? String(contentsOfFile: file, encoding: .utf8) { files[file] = text }
            }
        }
        // The pictures in docs/media are drawn by a script built with the app's sources, so it uses the catalog too
        files["scripts/render-media.swift"] = try? String(contentsOfFile: "scripts/render-media.swift", encoding: .utf8)
        precondition(files.count > 150)
        guard let label = try? NSRegularExpression(pattern: #"\b(systemName|systemSymbolName|systemImage):"#) else { preconditionFailure() }
        for (file, text) in files.sorted(by: { $0.key < $1.key }) where !drawers.contains(file) {
            for (index, line) in text.components(separatedBy: "\n").enumerated() where label.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                problems.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        precondition(problems.isEmpty, "draw these with a case of Symbol, like Image(.sunMaxFill), Label(\"Title\", symbol: .sunMaxFill), Button(\"Title\", symbol: .sunMaxFill) { } or NSImage(.sunMaxFill, accessibilityDescription: nil):\n" + problems.joined(separator: "\n"))
        print("no file but \(drawers.joined(separator: " and ")) writes systemName, systemSymbolName or systemImage: ok")

        let code = files.values.joined(separator: "\n")
        for symbol in all where code.range(of: #"\.\#(symbol)\b"#, options: .regularExpression) == nil {
            problems.append("\(symbol) = \"\(symbol.rawValue)\" isn't used anywhere: remove it from the catalog")
        }
        precondition(problems.isEmpty, problems.joined(separator: "\n"))
        print("every symbol in the catalog is used: ok")
    }
}
