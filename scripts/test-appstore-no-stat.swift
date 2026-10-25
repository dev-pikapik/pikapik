import Foundation

@main
enum TestAppStoreNoStat {
    static let sources = ["Core/Constants.swift", "Settings/SettingsSearch.swift", "Tools/Uninstaller/AppIdentity.swift", "Tools/Uninstaller/AppOwnerIndex.swift",
                          "Tools/Uninstaller/AppFootprint.swift", "Tools/Background/BackgroundTasks.swift"]
    static let checked = ["AppIdentity", "AppFootprint", "BackgroundTasks"]
    static let calls: Set<String> = ["_stat", "_lstat", "_fstat", "_fstatat", "_getattrlist", "_fgetattrlist", "_getattrlistat", "_getattrlistbulk"]

    @discardableResult
    static func run(_ arguments: [String], in folder: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        let output = Pipe()
        process.standardOutput = output
        try! process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "xcrun \(arguments.joined(separator: " "))")
        return text
    }

    static func main() {
        let fm = FileManager.default
        let repo = URL(fileURLWithPath: fm.currentDirectoryPath)
        let dir = fm.temporaryDirectory.appendingPathComponent("test-appstore-no-stat-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        for arch in ["arm64", "x86_64"] {
            let folder = dir.appendingPathComponent(arch)
            try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
            run(["swiftc", "-parse-as-library", "-D", "APPSTORE", "-module-name", "Pikapik", "-target", "\(arch)-apple-macos14.0", "-c"]
                + sources.map { repo.appendingPathComponent("Sources/pikapik/" + $0).path }, in: folder)
            for name in checked {
                let object = folder.appendingPathComponent(name + ".o")
                let symbols = run(["nm", "-u", object.path], in: folder).split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) }
                precondition(symbols.count > 10, "\(name).o (\(arch)) lists too few symbols")
                for symbol in symbols {
                    precondition(!calls.contains(String(symbol.prefix { $0 != "$" })), "\(name).swift calls \(symbol) in the App Store build (\(arch))")
                }
                let text = String(decoding: try! Data(contentsOf: object), as: UTF8.self).lowercased()
                precondition(!text.contains("modificationdate") && !text.contains("creationdate"), "\(name).swift reads a file date in the App Store build (\(arch))")
            }
        }
        print("appstore-no-stat: ok")
    }
}
