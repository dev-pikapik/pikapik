import AppKit
import Carbon

@main
enum TestLayout {
    static let spellingFile = "scripts/test-layout-spell.lzma"
    static let recording = CommandLine.arguments.dropFirst().first == "record"
    static var spelling: [String: [String]?] = [:]
    static var silence: (kind: String, language: String?)?

    static func recorded(_ kind: String, _ language: String?, _ text: String, live: () -> [String]?) -> [String]? {
        if let quiet = silence, quiet.kind == kind, quiet.language == nil || quiet.language == language {
            silence = nil
            return []
        }
        let parts = [kind, language ?? "", text]
        let key = parts.joined(separator: "\t")
        if let answer = spelling[key] { return answer }
        precondition(recording, "\(spellingFile) has no answer for \(parts.filter { !$0.isEmpty }.joined(separator: " ")), record the answers again with build/test-layout record")
        let answer = live()
        spelling.updateValue(answer, forKey: key)
        return answer
    }

    static func silent(_ kind: String, _ language: String? = nil, _ check: () -> Void) {
        silence = (kind, language)
        check()
        precondition(silence == nil, "the engine never asked for \(kind), so silencing it tested nothing")
    }

    static func precondition(_ condition: Bool, _ message: @autoclosure () -> String = "", line: UInt = #line) {
        if !condition { saveSpelling() }
        Swift.precondition(condition, message(), line: line)
    }

    static func saveSpelling() {
        guard recording else { return }
        let text = spelling.map { ([$0.key] + ($0.value ?? ["(nil)"])).joined(separator: "\t") }.sorted().joined(separator: "\n") + "\n"
        try! (Data(text.utf8) as NSData).compressed(using: .lzma).write(toFile: spellingFile, options: .atomic)
        print("layout: recorded \(spelling.count) spelling answers in \(spellingFile)")
    }

    static func replaySpelling() {
        if let data = FileManager.default.contents(atPath: spellingFile) {
            for line in String(decoding: try! (data as NSData).decompressed(using: .lzma) as Data, as: UTF8.self).split(separator: "\n") {
                let fields = line.components(separatedBy: "\t")
                let answer = Array(fields.dropFirst(3))
                spelling.updateValue(answer == ["(nil)"] ? nil : answer, forKey: fields.prefix(3).joined(separator: "\t"))
            }
        } else {
            precondition(recording, "\(spellingFile) is missing: record the spell checker's answers with build/test-layout record from the repo root")
        }
        for (live, recorded) in [
            (#selector(getter: NSSpellChecker.availableLanguages), #selector(NSSpellChecker.recordedLanguages)),
            (#selector(NSSpellChecker.checkSpelling(of:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:)), #selector(NSSpellChecker.recordedCheck(of:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:))),
            (#selector(NSSpellChecker.guesses(forWordRange:in:language:inSpellDocumentWithTag:)), #selector(NSSpellChecker.recordedGuesses(forWordRange:in:language:inSpellDocumentWithTag:))),
            (#selector(NSSpellChecker.completions(forPartialWordRange:in:language:inSpellDocumentWithTag:)), #selector(NSSpellChecker.recordedCompletions(forPartialWordRange:in:language:inSpellDocumentWithTag:))),
        ] {
            method_exchangeImplementations(class_getInstanceMethod(NSSpellChecker.self, live)!, class_getInstanceMethod(NSSpellChecker.self, recorded)!)
        }
    }

    static func layout(_ id: String) -> KeyboardLayout? {
        KeyboardLayouts.layout(id: "com.apple.keylayout." + id)
    }

    static func strokes(_ text: String, _ layout: KeyboardLayout) -> [Stroke]? {
        var result: [Stroke] = []
        for character in text {
            guard let strokes = layout.strokes(character, option: true) else { return nil }
            result += strokes
        }
        return result
    }

    static func fix(_ typed: String, _ source: KeyboardLayout, forced: Bool = false, ignored: Set<String> = []) -> LayoutFix? {
        KeyboardLayouts.fix(strokes(typed, source)!, from: source, forced: forced, ignored: ignored)
    }

    static func expect(_ value: String?, _ expected: String?, line: UInt = #line) {
        precondition(value == expected, "\(value ?? "nil") instead of \(expected ?? "nil")", line: line)
    }

    static func words(_ language: String) -> [String] {
        let data = (try? Data(contentsOf: URL(fileURLWithPath: "Resources/Localizable.xcstrings"))) ?? Data()
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: [String: Any]] ?? [:]
        let values = root.values.compactMap { item -> String? in
            guard let loc = (item["localizations"] as? [String: Any])?[language] as? [String: Any] else { return nil }
            if let value = (loc["stringUnit"] as? [String: Any])?["value"] as? String { return value }
            let plural = (loc["variations"] as? [String: Any])?["plural"] as? [String: Any]
            return ((plural?["many"] ?? plural?["other"]) as? [String: Any]).flatMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        precondition(!values.isEmpty, "no strings for \(language)")
        var words = Set<String>()
        for token in values.flatMap({ value in value.split(whereSeparator: \.isWhitespace) }) where !token.contains("%") {
            words.insert(String(token))
            if let core = KeyboardLayouts.core(String(token)) { words.insert(core) }
        }
        return words.sorted()
    }

    static func falsePositives(_ words: [String], _ layout: KeyboardLayout) -> (checked: Int, found: [String]) {
        var checked = 0
        var found: [String] = []
        for word in words {
            guard let keys = strokes(word, layout) else { continue }
            checked += 1
            if let fix = KeyboardLayouts.fix(keys, from: layout) { found.append("\(fix.original) → \(fix.text)") }
        }
        return (checked, found)
    }

    static func rate(_ words: [String], typed native: KeyboardLayout, in source: KeyboardLayout) -> String {
        var fixed = 0, total = 0
        for word in words where word.count >= 4 && KeyboardLayouts.isPlain(word) {
            guard let keys = strokes(word, native) else { continue }
            total += 1
            if KeyboardLayouts.fix(keys, from: source)?.text == word { fixed += 1 }
        }
        return "\(fixed) of \(total)"
    }

    static func main() {
        setbuf(stdout, nil)
        replaySpelling()
        precondition(KeyboardLayouts.wanted(["ru-MD", "en-MD", "ru-RU", "zh-Hans-CN"], covered: ["en"]) == ["ru", "zh"])
        precondition(KeyboardLayouts.wanted(["en-US"], covered: ["en"]).isEmpty)
        print("layout: the layouts to offer are the preferred languages nobody covers yet, once each: ok")
        KeyboardLayouts.extraLanguages = ["en"]
        guard let us = layout("US"), let ru = layout("Russian"), let uk = layout("Ukrainian"), let de = layout("German"), let fr = layout("French"), let el = layout("Greek") else { fatalError("missing layouts") }

        KeyboardLayouts.all = [us, ru]
        expect(fix("ghbdtn", us)?.text, "привет")
        expect(fix("ghbdtn", us)?.original, "ghbdtn")
        expect(fix("z nt,z k.,k.", us)?.text, "я тебя люблю")
        expect(fix("I said ghbdtn", us)?.original, "ghbdtn")
        expect(fix("I said ghbdtn", us)?.text, "привет")
        expect(fix("z 2 rjnf", us)?.text, "я 2 кота")
        expect(fix("руддщ цщкдв", ru)?.text, "hello world")
        expect(fix("GHBDTN", us)?.text, "ПРИВЕТ")
        expect(fix("ghbdtn", us, ignored: ["ghbdtn"])?.text, nil)
        expect(fix("z nt,z k.,k.", us, ignored: ["nt,z"])?.text, "люблю")
        expect(fix("lf", us)?.text, nil)
        expect(fix("lf", us, forced: true)?.text, "да")
        expect(fix("ghbdtn ", us, forced: true)?.text, "привет ")
        expect(fix("привет", ru)?.text, nil)
        expect(fix("hello", us)?.text, nil)
        precondition(KeyboardLayouts.fix(strokes("ghbdtn", us)! + [Stroke(key: 14, modifiers: 8)], from: us) == nil)
        expect(KeyboardLayouts.convert("Ghbdtn? vbh!", from: us, to: ru), "Привет? мир!")
        expect(KeyboardLayouts.variants("ghbdtn").first?.text, "привет")
        expect(KeyboardLayouts.variants("руддщ цщкдв").first?.text, "hello world")
        expect(fr.translate(strokes("être", fr)!).text, "être")
        if let windows = layout("RussianWin") {
            for order in [[windows, us], [us, windows]] {
                KeyboardLayouts.all = order
                expect(KeyboardLayouts.variants("ghbdtn vbh").map(\.text).joined(separator: "|"), "привет мир")
                expect(KeyboardLayouts.variants("привет мир").map(\.text).joined(separator: "|"), "ghbdtn vbh")
            }
            KeyboardLayouts.all = [us, ru]
        }

        KeyboardLayouts.all = [us, de]
        expect(fix("yeit", us)?.text, nil)
        expect(fix("yeit", us, forced: true)?.text, "zeit")

        KeyboardLayouts.all = [us, ru]
        expect(fix("frnt", us)?.text, nil)
        expect(fix("игпы", ru)?.text, nil)
        expect(fix("ghbDtn", us)?.text, nil)
        if let german = layout("German") {
            KeyboardLayouts.all = [german, ru]
            expect(fix("pder", german)?.text, nil)
        }

        KeyboardLayouts.all = [us, ru, uk]
        expect(fix(us.translate(strokes("привіт", uk)!).text, us)?.text, "привіт")
        expect(fix("ghbdtn", us)?.text, "привет")

        KeyboardLayouts.all = [us, el]
        expect(fix(us.translate(strokes("ευχαριστώ", el)!).text, us)?.text, "ευχαριστώ")

        if let arabic = layout("Arabic") {
            KeyboardLayouts.all = [us, arabic]
            expect(fix("dont", us)?.text, nil)
        }

        var failures: [String] = []
        let corpus = [("ar", "Arabic"), ("cs", "Czech"), ("de", "German"), ("en", "US"), ("es", "Spanish-ISO"), ("fr", "French"), ("hi", "Devanagari"), ("id", "US"), ("it", "Italian"), ("nl", "Dutch"), ("pl", "Polish"), ("pt-BR", "Brazilian"), ("ro", "Romanian"), ("ru", "Russian"), ("sv", "Swedish"), ("tr", "Turkish-QWERTY"), ("uk", "Ukrainian"), ("vi", "Vietnamese")]
        for (language, id) in corpus {
            guard let native = layout(id) else { print("\(language): no layout \(id)"); continue }
            KeyboardLayouts.extraLanguages = ["en", String(language.prefix(2))]
            KeyboardLayouts.all = [native] + [us, ru].filter { $0.id != native.id }
            let result = falsePositives(words(language), native)
            print("\(language): \(result.found.count) false of \(result.checked)")
            failures += result.found.map { "\(language): \($0)" }
        }

        KeyboardLayouts.extraLanguages = ["en"]
        KeyboardLayouts.all = [us] + ["Russian", "Ukrainian", "Greek", "Hebrew", "Arabic", "Devanagari"].compactMap { layout($0) }
        let lines = ((try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)) ?? "").split(separator: "\n")
        let names = ((try? String(contentsOfFile: "/usr/share/dict/propernames", encoding: .utf8)) ?? "").split(separator: "\n")
        let english = stride(from: 0, to: lines.count, by: 10).map { String(lines[$0]) } + names.map(String.init)
        let result = falsePositives(english, us)
        print("dict: \(result.found.count) false of \(result.checked)")
        failures += result.found.map { "dict: \($0)" }

        for (language, id) in [("ru", "Russian"), ("uk", "Ukrainian"), ("ar", "Arabic")] {
            guard let native = layout(id) else { continue }
            KeyboardLayouts.all = [us, native]
            KeyboardLayouts.extraLanguages = ["en", language]
            print("\(language) typed in US, fixed: \(rate(words(language), typed: native, in: us)); en typed in \(id): \(rate(words("en"), typed: us, in: native))")
        }

        for failure in failures { print(failure) }
        precondition(failures.isEmpty, "\(failures.count) false fixes")

        KeyboardLayouts.extraLanguages = ["en"]
        KeyboardLayouts.all = [us, ru]
        silent("guesses") { expect(fix("geat", us)?.text, nil) }
        if let arabic = layout("Arabic") {
            KeyboardLayouts.all = [us, arabic]
            silent("completions", us.dictionary) { expect(fix("kumbi", us)?.text, nil) }
        }
        print("layout: an English word stays as typed when the spell checker leaves one question unanswered: ok")
        saveSpelling()
        print("layout: ok")
    }
}

extension NSSpellChecker {
    @objc dynamic func recordedLanguages() -> [String] {
        TestLayout.recorded("languages", nil, "") { recordedLanguages() } ?? []
    }

    @objc dynamic func recordedCheck(of text: String, startingAt start: Int, language: String?, wrap: Bool, inSpellDocumentWithTag tag: Int, wordCount: UnsafeMutablePointer<Int>?) -> NSRange {
        let found = (TestLayout.recorded("check", language, text) {
            let range = recordedCheck(of: text, startingAt: start, language: language, wrap: wrap, inSpellDocumentWithTag: tag, wordCount: wordCount)
            return range.location == NSNotFound ? [] : [String(range.location), String(range.length)]
        } ?? []).compactMap { Int($0) }
        return found.count == 2 ? NSRange(location: found[0], length: found[1]) : NSRange(location: NSNotFound, length: 0)
    }

    @objc dynamic func recordedGuesses(forWordRange range: NSRange, in text: String, language: String?, inSpellDocumentWithTag tag: Int) -> [String]? {
        TestLayout.recorded("guesses", language, (text as NSString).substring(with: range)) { recordedGuesses(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag) }
    }

    @objc dynamic func recordedCompletions(forPartialWordRange range: NSRange, in text: String, language: String?, inSpellDocumentWithTag tag: Int) -> [String]? {
        TestLayout.recorded("completions", language, (text as NSString).substring(with: range)) { recordedCompletions(forPartialWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag) }
    }
}
