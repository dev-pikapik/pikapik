import Foundation

@main
enum TestSettingsFolder {
    static let manager = FileManager.default

    static func save(_ folder: URL, _ modified: Double) {
        try! manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try! SettingsFile(settings: ["pet": true], modified: Date(timeIntervalSince1970: modified), device: folder.lastPathComponent)
            .data().write(to: folder.appendingPathComponent(SettingsFile.name))
    }

    static func stamp(_ folder: URL) -> Double? {
        (try? Data(contentsOf: folder.appendingPathComponent(SettingsFile.name))).flatMap(SettingsFile.init(data:))?.modified.timeIntervalSince1970
    }

    static func found(_ url: URL) -> String {
        switch SettingsFile.read(url) {
        case .success(.none): "none"
        case .success(.some(let file)): "file \(Int(file.modified.timeIntervalSince1970))"
        case .failure: "unreadable"
        }
    }

    static func move(_ root: URL, old: Double, new: Double?, extra: Bool = false) -> (old: URL, new: URL) {
        let from = root.appendingPathComponent("pikapik"), to = root.appendingPathComponent("pikapik")
        save(from, old)
        if let new { save(to, new) }
        if extra { try! Data("notes".utf8).write(to: from.appendingPathComponent("notes.txt")) }
        SettingsFile.moveFolder(from: from, to: to)
        return (from, to)
    }

    static func main() {
        let root = manager.temporaryDirectory.appendingPathComponent("test-settings-folder-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }

        var folders = move(root.appendingPathComponent("only-old"), old: 100, new: nil)
        precondition(!manager.fileExists(atPath: folders.old.path) && stamp(folders.new) == 100)

        folders = move(root.appendingPathComponent("old-newer"), old: 200, new: 100)
        precondition(!manager.fileExists(atPath: folders.old.path) && stamp(folders.new) == 200)

        folders = move(root.appendingPathComponent("new-newer"), old: 100, new: 200)
        precondition(!manager.fileExists(atPath: folders.old.path) && stamp(folders.new) == 200)

        folders = move(root.appendingPathComponent("other-files"), old: 300, new: 200, extra: true)
        precondition(stamp(folders.new) == 300 && manager.fileExists(atPath: folders.old.appendingPathComponent("notes.txt").path))

        let unread = root.appendingPathComponent("new-unreadable/pikapik").appendingPathComponent(SettingsFile.name)
        try! manager.createDirectory(at: unread.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("{".utf8).write(to: unread)
        folders = move(root.appendingPathComponent("new-unreadable"), old: 300, new: nil)
        precondition(stamp(folders.old) == 300 && (try? Data(contentsOf: unread)) == Data("{".utf8))

        print("settings folder: ok")

        let reads = root.appendingPathComponent("read")
        let file = reads.appendingPathComponent(SettingsFile.name)
        precondition(found(file) == "none", "no file: nothing to keep, so sync may upload")
        save(reads, 500)
        precondition(found(file) == "file 500", "a settings file is read: \(found(file))")
        try! Data("{".utf8).write(to: file)
        precondition(found(file) == "none", "a damaged file may be replaced")
        try! Data(count: SettingsFile.maxSize + 1).write(to: file)
        precondition(found(file) == "none", "a file over 2 MB may be replaced")
        try! manager.removeItem(at: file)
        try! manager.createDirectory(at: file, withIntermediateDirectories: false)
        precondition(found(file) == "unreadable", "a file that can't be read now must never be replaced")
        try! manager.removeItem(at: file)
        if getuid() != 0 {
            save(reads, 600)
            try! manager.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
            precondition(found(file) == "unreadable", "a file pikapik may not read must never be replaced")
            try! manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        print("sync tells a missing or damaged file from one it can't read yet: ok")

        let real = Date(timeIntervalSince1970: 1_791_234_567)
        let first = SettingsFile.unclaimed(at: real), second = SettingsFile.unclaimed(at: real.addingTimeInterval(60))
        func upload(_ modified: Date, from device: String) -> SettingsFile { SettingsFile(settings: [:], modified: modified, device: device) }
        precondition(first > Date(timeIntervalSince1970: 0) && first < Date(timeIntervalSince1970: 86_400) && second < first && SettingsFile.unclaimed(at: real.addingTimeInterval(1)) < first, "such a time lies in the first day of 1970, earlier for a later upload")
        precondition(SettingsFile.merge(local: real, remote: upload(second, from: "new-mac"), device: "old-mac") == .upload, "a Mac with settings keeps them when a new Mac's first upload arrives, and sends them back")
        precondition(SettingsFile.merge(local: second, remote: upload(real, from: "old-mac"), device: "new-mac") == .apply, "the new Mac then takes them")
        precondition(SettingsFile.merge(local: first, remote: upload(second, from: "new-mac"), device: "first-mac") == .upload, "of two Macs that turn sync on before iCloud has anything, the first keeps its settings")
        precondition(SettingsFile.merge(local: second, remote: upload(first, from: "first-mac"), device: "new-mac") == .apply, "and the second takes them")
        precondition(SettingsFile.merge(local: .distantPast, remote: upload(second, from: "new-mac"), device: "third-mac") == .apply, "a Mac that turns sync on later still takes what is in iCloud")
        let sent = SettingsFile.unclaimed()
        try! upload(sent, from: "new-mac").data().write(to: file)
        precondition((try? SettingsFile.read(file).get())?.modified == sent, "such a time comes back exactly, so the Mac that sent it sees nothing new")
        print("an upload that no change on this Mac caused loses to every real file: ok")
    }
}
