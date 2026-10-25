import Foundation

@main
struct TestConstants {
    static let constants = "Sources/pikapik/Core/Constants.swift"
    static let forms = ".github/ISSUE_TEMPLATE"

    struct Name {
        let line: Int
        let owner: String
        let name: String
        let texts: [String]
        let isList: Bool
        var key: String { owner + "." + name }
    }

    struct Reader {
        var code: [UInt8]
        var literals: [(line: Int, text: String)] = []
        var lists: [(line: Int, texts: [String])] = []
        var i = 0
        var line = 1
        var open: [(line: Int, texts: [String]?)] = []

        init(_ text: String) {
            code = Array(text.utf8)
            expression(nested: false)
        }

        func at(_ k: Int) -> UInt8 { k < code.count ? code[k] : 0 }

        func hashes(_ k: Int, _ count: Int) -> Bool { (0..<count).allSatisfy { at(k + $0) == 0x23 } }

        func closes(_ k: Int, _ quotes: Int, _ count: Int) -> Bool { (0..<quotes).allSatisfy { at(k + $0) == 0x22 } && hashes(k + quotes, count) }

        mutating func skip(blank: Bool = false) {
            if code[i] == 0x0A { line += 1 } else if blank { code[i] = 0x20 }
            i += 1
        }

        mutating func taint() {
            if !open.isEmpty { open[open.count - 1].texts = nil }
        }

        mutating func expression(nested: Bool) {
            var depth = 0
            while i < code.count {
                if at(i) == 0x2F && at(i + 1) == 0x2F {
                    while i < code.count && code[i] != 0x0A { skip(blank: true) }
                    continue
                }
                if at(i) == 0x2F && at(i + 1) == 0x2A {
                    var level = 0
                    repeat {
                        if at(i) == 0x2F && at(i + 1) == 0x2A {
                            level += 1
                            skip(blank: true)
                        } else if at(i) == 0x2A && at(i + 1) == 0x2F {
                            level -= 1
                            skip(blank: true)
                        }
                        skip(blank: true)
                    } while level > 0 && i < code.count
                    continue
                }
                var count = 0
                while at(i + count) == 0x23 { count += 1 }
                if at(i + count) == 0x22 {
                    string(count)
                    continue
                }
                if count > 0 && at(i + count) == 0x2F {
                    i += count + 1
                    while i < code.count && !(code[i] == 0x2F && hashes(i + 1, count)) { skip() }
                    i += count + 1
                    taint()
                    continue
                }
                switch code[i] {
                case 0x5B:
                    open.append((line, []))
                case 0x5D:
                    if let list = open.popLast(), let texts = list.texts, !texts.isEmpty { lists.append((list.line, texts)) }
                    taint()
                case 0x28:
                    depth += 1
                    taint()
                case 0x29 where nested && depth == 0:
                    i += 1
                    return
                case 0x29:
                    depth -= 1
                    taint()
                case 0x09, 0x0A, 0x0D, 0x20, 0x2C:
                    break
                default:
                    taint()
                }
                skip()
            }
        }

        mutating func string(_ count: Int) {
            let start = line
            let quotes = at(i + count + 1) == 0x22 && at(i + count + 2) == 0x22 ? 3 : 1
            i += count + quotes
            let from = i
            var plain = true
            while i < code.count && !closes(i, quotes, count) {
                if code[i] == 0x5C && hashes(i + 1, count) {
                    i += count + 1
                    if at(i) == 0x28 {
                        plain = false
                        i += 1
                        expression(nested: true)
                        continue
                    }
                }
                if i < code.count { skip() }
            }
            var text = String(decoding: code[from..<min(i, code.count)], as: UTF8.self)
            i += quotes + count
            if quotes == 3 {
                var lines = text.components(separatedBy: "\n")
                let indent = lines.removeLast()
                text = lines.dropFirst().map { $0.hasPrefix(indent) ? String($0.dropFirst(indent.count)) : $0 }.joined(separator: "\n")
            }
            literals.append((start, text))
            if plain && !open.isEmpty { open[open.count - 1].texts?.append(text) } else { taint() }
        }
    }

    static func unnamed(_ reader: Reader, _ texts: [String: String], _ lists: [[String]: String]) -> [(line: Int, text: String, key: String)] {
        reader.literals.compactMap { literal in texts[literal.text].map { (literal.line, "\"\(literal.text)\"", $0) } }
            + reader.lists.compactMap { list in lists[list.texts].map { (list.line, "\(list.texts)", $0) } }
    }

    static func expand(_ path: String) -> [String] {
        guard let open = path.firstIndex(of: "{"), let close = path[open...].firstIndex(of: "}") else { return [path] }
        return path[path.index(after: open)..<close].split(separator: ",", omittingEmptySubsequences: false).flatMap {
            expand(String(path[..<open]) + $0 + path[path.index(after: close)...])
        }
    }

    static func check(_ problems: [String], _ done: String) {
        precondition(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
        print(done + ": ok")
    }

    static func main() {
        let sample = ##"""
        let a = "/usr/bin/tar" // "/usr/bin/tar"
        /* "/usr/bin/tar" /* "/usr/bin/tar" */ "/usr/bin/tar" */
        let b = "say \"hi\" \(on ? "/usr/bin/tar" : "\("no")")"
        let c = """
            "quoted" // \("/usr/bin/tar")
            """
        let d = #"raw "quoted" \(no) \#("/usr/bin/tar")"#
        let e = #/"(.*)"/#, f = ["/opt/homebrew", "/usr/local"], g = [x, "/usr/local"]
        """##
        let read = Reader(sample)
        precondition(read.literals.map(\.text) == [
            "/usr/bin/tar", "/usr/bin/tar", "no", #"\("no")"#, #"say \"hi\" \(on ? "/usr/bin/tar" : "\("no")")"#,
            "/usr/bin/tar", #""quoted" // \("/usr/bin/tar")"#, "/usr/bin/tar", ##"raw "quoted" \(no) \#("/usr/bin/tar")"##,
            "/opt/homebrew", "/usr/local", "/usr/local",
        ], "\(read.literals)")
        let found = unnamed(read, ["/usr/bin/tar": "SystemPath.tar"], [["/opt/homebrew", "/usr/local"]: "SystemPath.homebrewPrefixes"])
        precondition(found.map { "\($0.line) \($0.key)" } == ["1 SystemPath.tar", "3 SystemPath.tar", "5 SystemPath.tar", "7 SystemPath.tar", "8 SystemPath.homebrewPrefixes"], "\(found)")
        precondition(expand("Tools/{A,B}.swift") == ["Tools/A.swift", "Tools/B.swift"] && expand("x{,Y}{1,2}") == ["x1", "x2", "xY1", "xY2"])
        print("comments are skipped, strings are read inside interpolations, multi-line and raw strings, and build.sh braces expand: ok")

        var problems: [String] = []
        var names: [Name] = []
        var owner: String?
        for (index, line) in ((try? String(contentsOfFile: constants, encoding: .utf8)) ?? "").components(separatedBy: "\n").enumerated() where !line.isEmpty {
            if let current = owner {
                if line == "}" {
                    owner = nil
                } else if let match = line.wholeMatch(of: #/ {4}static let ([a-z][A-Za-z0-9]*) = ("[^"\\]+"|URL\(string: "[^"\\]+"\)!|\["[^"\\]+"(?:, "[^"\\]+")*\])/#) {
                    names.append(Name(line: index + 1, owner: current, name: String(match.1), texts: Reader(String(match.2)).literals.map(\.text), isList: match.2.first == "["))
                } else {
                    problems.append("\(constants):\(index + 1): \(line.trimmingCharacters(in: .whitespaces)) is not static let name = \"text\", URL(string: \"text\")! or a list of texts")
                }
            } else if let match = line.wholeMatch(of: #/enum ([A-Z][A-Za-z]*) \{/#) {
                owner = String(match.1)
            } else if line != "import Foundation" {
                problems.append("\(constants):\(index + 1): \(line) is outside the enums")
            }
        }
        precondition(names.count > 100, "only \(names.count) names in \(constants): run from the repo root")
        check(problems, "all \(names.count) names in \(constants) are a text, a link or a list of texts")

        var readers: [(file: String, reader: Reader)] = []
        for path in (FileManager.default.enumerator(atPath: "Sources")?.compactMap { $0 as? String } ?? []).sorted() where path.hasSuffix(".swift") {
            let file = "Sources/" + path
            readers.append((file, Reader((try? String(contentsOfFile: file, encoding: .utf8)) ?? "")))
        }
        precondition(readers.count > 150, "only \(readers.count) files in Sources")
        let reference = try! NSRegularExpression(pattern: #"\b(?:"# + Set(names.map(\.owner)).joined(separator: "|") + #")\.\w+\b"#)
        var used: Set<String> = []
        for (file, reader) in readers where file != constants {
            let code = String(decoding: reader.code, as: UTF8.self)
            for match in reference.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                used.insert((code as NSString).substring(with: match.range))
            }
        }
        for name in names where !used.contains(name.key) {
            problems.append("\(constants):\(name.line): \(name.key) isn't used anywhere in Sources: remove it")
        }
        check(problems, "every name is used in Sources")

        var values: [String: Name] = [:]
        for name in names {
            let value = "\(name.owner) \(name.isList) \(name.texts)"
            if let first = values[value], Set([first.key, name.key]) != ["AppConstants.bundleIDPrefix", "AppConstants.appStoreBundleID"] {
                problems.append("\(constants):\(name.line): \(name.key) holds the same value as \(first.key): keep one name")
            } else {
                values[value] = name
            }
        }
        check(problems, "no value has two names in one enum, apart from bundleIDPrefix and appStoreBundleID")

        let script = (try? String(contentsOfFile: "scripts/build.sh", encoding: .utf8)) ?? ""
        let build = Set(script.matches(of: #/Sources/[\w./{},-]+\.swift/#).flatMap { expand(String($0.output)) })
        precondition(build.count >= 5, "only \(build.count) files from Sources in scripts/build.sh")
        var texts: [String: String] = [:]
        var lists: [[String]: String] = [:]
        for name in names where ["PreferenceKey", "SystemPath", "SystemPane"].contains(name.owner) || name.owner == "AppConstants" && name.texts.contains(where: { $0.contains { ".:/".contains($0) } }) {
            if name.isList { lists[name.texts] = name.key } else { texts[name.texts[0]] = texts[name.texts[0]].map { "\($0) or \(name.key)" } ?? name.key }
        }
        let skipped = build.union([constants])
        for (file, reader) in readers where !skipped.contains(file) {
            problems += unnamed(reader, texts, lists).map { "\(file):\($0.line): \($0.text) is \($0.key): write the name" }
        }
        check(problems, "no file in Sources writes a named value as text (\(build.count) files built by build.sh left out)")

        var links = 0
        for (file, reader) in readers {
            for literal in reader.literals where literal.text.contains("template=") {
                for match in literal.text.matches(of: #/template=([\w.-]+)/#) {
                    links += 1
                    if !FileManager.default.fileExists(atPath: "\(forms)/\(match.1)") {
                        problems.append("\(file):\(literal.line): template=\(match.1) is not a form in \(forms)")
                    }
                }
            }
        }
        check(problems, "every link to an issue form (\(links)) names a form in \(forms)")
    }
}
