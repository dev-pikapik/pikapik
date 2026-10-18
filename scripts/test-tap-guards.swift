import Foundation

@main
struct TestTapGuards {
    static let checks = [
        "accessibility": ["AXIsProcessTrusted()", "Permissions.shared.accessibility"],
        "inputMonitoring": ["CGPreflightListenEventAccess()", "Permissions.shared.inputMonitoring"],
    ]

    static func needs(_ lines: [String]) -> [String] {
        let declared = lines.filter { $0.contains("var needs: [Permission]") }.joined()
        return checks.keys.filter { declared.contains("." + $0) }
    }

    static func functions(_ lines: [String]) -> [(line: Int, name: String)] {
        let pattern = try! NSRegularExpression(pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        return lines.indices.compactMap { index in
            let line = lines[index]
            guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let found = Range(match.range(at: 1), in: line) else { return nil }
            return (line: index, name: String(line[found]))
        }
    }

    static func checked(_ lines: [String], from: Int, to: Int, wanted: [String]) -> Bool {
        let text = lines[from...to].joined(separator: "\n")
        return checks.values.joined().contains { text.contains($0) }
            && wanted.allSatisfy { kind in checks[kind, default: []].contains { text.contains($0) } }
    }

    static func calls(_ lines: [String], _ name: String) -> [Int] {
        let pattern = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: name) + #"\("#)
        return lines.indices.filter { index in
            let line = lines[index]
            return pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).contains { match in
                guard let range = Range(match.range, in: line) else { return false }
                let before = String(line[..<range.lowerBound])
                if before.trimmingCharacters(in: .whitespaces).hasSuffix("func") { return false }
                return !before.hasSuffix(".") || before.hasSuffix("self.") || before.hasSuffix("self?.")
            }
        }
    }

    /// Lines of event taps created before pikapik checked the permission they need, in the tap's own
    /// function or in every function that calls it.
    static func unguarded(_ text: String) -> [Int] {
        let lines = text.components(separatedBy: "\n")
        let funcs = functions(lines)
        let wanted = needs(lines)
        func owner(_ line: Int) -> (line: Int, name: String)? { funcs.last { $0.line <= line } }
        return lines.indices.filter { index in
            guard lines[index].contains("CGEvent.tapCreate(") else { return false }
            guard let function = owner(index) else { return true }
            if checked(lines, from: function.line, to: index, wanted: wanted) { return false }
            let sites = calls(lines, function.name)
            return sites.isEmpty || sites.contains { site in
                guard let caller = owner(site) else { return true }
                return !checked(lines, from: caller.line, to: site, wanted: wanted)
            }
        }.map { $0 + 1 }
    }

    static func main() {
        let callerGuard = """
        var needs: [Permission] { [.accessibility, .inputMonitoring] }
        func refresh() {
            stop()
            guard isEnabled, MainCopy.canAct, AXIsProcessTrusted(), Permissions.shared.inputMonitoring else { return }
            startTap()
        }
        private func startTap() {
            guard let tap = CGEvent.tapCreate(
        """
        let sameLine = """
        func refresh() { if isEnabled, MainCopy.canAct, AXIsProcessTrusted() { start() } }
        private func start() {
            guard let tap = CGEvent.tapCreate(
        """
        let inside = """
        static func start() {
            if AXIsProcessTrusted(), let tap = CGEvent.tapCreate(
        """
        let missing = """
        func refresh() {
            stop()
            if isEnabled, MainCopy.canAct { start() }
        }
        private func start() {
            PetStage.shared.start()
            guard let tap = CGEvent.tapCreate(
        """
        let wrongCheck = """
        var needs: [Permission] { [.inputMonitoring] }
        func refresh() { if isEnabled, AXIsProcessTrusted() { start() } }
        private func start() {
            guard let tap = CGEvent.tapCreate(
        """
        let otherObject = """
        func refresh() { if AXIsProcessTrusted() { other.start() } }
        private func start() {
            guard let tap = CGEvent.tapCreate(
        """
        precondition([callerGuard, sameLine, inside].allSatisfy { unguarded($0).isEmpty })
        precondition(unguarded(missing) == [7])
        precondition(unguarded(wrongCheck) == [4])
        precondition(unguarded(otherObject) == [3])
        print("an event tap counts as checked only after the permission its tool needs is checked: ok")

        let files = FileManager.default.enumerator(atPath: "Sources")?.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        precondition(files.count > 50)
        var taps = 0
        var bad: [String] = []
        for file in files.sorted() {
            guard let text = try? String(contentsOfFile: "Sources/" + file, encoding: .utf8) else { continue }
            taps += text.components(separatedBy: "CGEvent.tapCreate(").count - 1
            bad += unguarded(text).map { "\(file):\($0)" }
        }
        precondition(taps > 10)
        precondition(bad.isEmpty, "These event taps are created before pikapik checks the permission they need, so macOS shows its own request at launch or wake instead of leaving it to the Permissions tab: \(bad)")
        print("every event tap in Sources checks its permission first (\(taps) taps): ok")
    }
}
