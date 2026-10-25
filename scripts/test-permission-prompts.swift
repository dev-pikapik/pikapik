import Foundation

@main
enum TestPermissionPrompts {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)
        let until = now.addingTimeInterval(PermissionPolling.afterAllow)
        precondition(PermissionPolling.continues(pageShown: true, askedUntil: .distantPast, askedGranted: true, now: now), "the Permissions page checks while it is on screen")
        precondition(!PermissionPolling.continues(pageShown: false, askedUntil: .distantPast, askedGranted: true, now: now), "nothing checks once the page is gone and nothing was asked")
        precondition(PermissionPolling.continues(pageShown: false, askedUntil: until, askedGranted: false, now: now), "after Allow it keeps checking while System Settings covers the page")
        precondition(!PermissionPolling.continues(pageShown: false, askedUntil: until, askedGranted: true, now: now), "and stops once macOS grants it")
        precondition(!PermissionPolling.continues(pageShown: false, askedUntil: until, askedGranted: false, now: until.addingTimeInterval(1)), "or two minutes after Allow")
        print("permissions are checked only while the page is shown, and after Allow until granted or two minutes later: ok")

        let files = FileManager.default.enumerator(atPath: "Sources")?.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        precondition(files.count > 50)
        let prompts = ["AXIsProcessTrustedWithOptions", "CGRequestListenEventAccess", "CGRequestScreenCaptureAccess", "CGRequestPostEventAccess"]
        var prompting: [String] = [], requests: [String] = []
        for file in files {
            let text = try! String(contentsOfFile: "Sources/" + file, encoding: .utf8)
            if prompts.contains(where: text.contains) { prompting.append(file) }
            for line in text.components(separatedBy: "\n") where line.range(of: #"\brequest\("#, options: .regularExpression) != nil && !line.contains("func request(") {
                requests.append(file + ": " + line.trimmingCharacters(in: .whitespaces))
            }
        }
        precondition(prompting == ["pikapik/Permissions/Permissions.swift"], "Only Permissions.swift may call what shows a macOS permission prompt: \(prompting)")
        precondition(requests == ["pikapik/Permissions/Permissions.swift: permissions.request([self])"],
                     "Only Allow on the Permissions page may ask macOS; rows and bars elsewhere only open that page: \(requests)")
        print("only Allow on the Permissions page shows a macOS permission prompt (\(files.count) files): ok")
    }
}
