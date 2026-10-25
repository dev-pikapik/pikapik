import AppKit

@main
struct TestSymbols {
    static let catalog = "Sources/pikapik/Core/Symbol.swift"

    /// "sun.max.fill" is `sunMaxFill`, and a name that starts with a digit gets "number" in front.
    static func caseName(_ name: String) -> String {
        let parts = name.split(separator: ".").map(String.init)
        let joined = parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return joined.first?.isNumber == true ? "number" + joined : joined
    }

    /// The expression after each `systemName:`, `systemSymbolName:` or `systemImage:` label, up to the comma or bracket that ends the argument.
    static func arguments(_ text: String) -> [(line: Int, expression: String)] {
        guard let label = try? NSRegularExpression(pattern: #"\b(systemName|systemSymbolName|systemImage):"#) else { return [] }
        let chars = Array(text.utf16)
        var found: [(line: Int, expression: String)] = []
        for match in label.matches(in: text, range: NSRange(location: 0, length: chars.count)) {
            var i = match.range.location + match.range.length
            var depth = 0
            var quoted = false
            while i < chars.count {
                let c = chars[i]
                if quoted {
                    if c == 0x5C { i += 1 } else if c == 0x22 { quoted = false }
                } else if c == 0x22 {
                    quoted = true
                } else if c == 0x28 || c == 0x5B || c == 0x7B {
                    depth += 1
                } else if c == 0x29 || c == 0x5D || c == 0x7D || c == 0x2C || c == 0x0A {
                    if depth == 0 { break }
                    if c != 0x2C && c != 0x0A { depth -= 1 }
                }
                i += 1
            }
            let start = match.range.location + match.range.length
            let line = chars[..<match.range.location].filter { $0 == 0x0A }.count + 1
            found.append((line: line, expression: String(decoding: chars[start..<min(i, chars.count)], as: UTF16.self)))
        }
        return found
    }

    static func literals(_ expression: String) -> [String] {
        guard let literal = try? NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#) else { return [] }
        return literal.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)).compactMap {
            Range($0.range(at: 1), in: expression).map { String(expression[$0]) }
        }
    }

    static func main() {
        let sample = """
        Image(systemName: "a.b")
        Image(systemName: on ? "c" : "d.e").foregroundStyle(.red)
        Label("Title, with a comma", systemImage: "f")
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
        Button("x", systemImage: list[min(i, 2)]) { }
        """
        let parsed = arguments(sample)
        precondition(parsed.map { $0.line } == [1, 2, 3, 4, 5] && parsed.map { literals($0.expression) } == [["a.b"], ["c", "d.e"], ["f"], [], []], "\(parsed)")
        precondition(caseName("sun.max.fill") == "sunMaxFill" && caseName("speaker.wave.2.fill") == "speakerWave2Fill" && caseName("7.square.fill") == "number7SquareFill")
        print("symbol names are found after systemName, systemSymbolName and systemImage, both sides of a ?: included: ok")

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
        let names = Set(all.map(\.rawValue))
        var written = 0
        for (file, text) in files.sorted(by: { $0.key < $1.key }) {
            for (line, expression) in arguments(text) {
                for name in literals(expression) {
                    written += 1
                    if name.contains("\\(") {
                        problems.append("\(file):\(line): \"\(name)\" puts a symbol name together from pieces; pick whole names from Symbol")
                    } else if !names.contains(name) {
                        problems.append("\(file):\(line): \"\(name)\" is not in \(catalog)")
                    }
                }
            }
        }
        precondition(problems.isEmpty, problems.joined(separator: "\n"))
        print("all \(written) symbol names written next to systemName, systemSymbolName or systemImage are in the catalog: ok")

        let code = files.values.joined(separator: "\n")
        for symbol in all where !code.contains("\"\(symbol.rawValue)\"") && code.range(of: #"\.\#(symbol)\b"#, options: .regularExpression) == nil {
            problems.append("\(symbol) = \"\(symbol.rawValue)\" isn't used anywhere: remove it from the catalog")
        }
        precondition(problems.isEmpty, problems.joined(separator: "\n"))
        print("every symbol in the catalog is used: ok")
    }
}
