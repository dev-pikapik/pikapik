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
        let from = root.appendingPathComponent("previous"), to = root.appendingPathComponent("pikapik")
        save(from, old)
        if let new { save(to, new) }
        if extra { try! Data("notes".utf8).write(to: from.appendingPathComponent("notes.txt")) }
        SettingsFile.moveFolder(from: from, to: to)
        return (from, to)
    }

    static func main() {
        let root = manager.temporaryDirectory.appendingPathComponent("test-settings-folder-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }

        let unchanged = root.appendingPathComponent("unchanged")
        save(unchanged, 100)
        SettingsFile.moveFolder(from: unchanged, to: unchanged)
        precondition(stamp(unchanged) == 100)

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

        let twin = upload(real.addingTimeInterval(60), from: "copied")
        precondition(SettingsFile.copiedDevice(local: real, remote: twin, device: "copied"), "a later file with this Mac's id came from a Mac that got the id from Migration Assistant or a backup")
        precondition(!SettingsFile.copiedDevice(local: real.addingTimeInterval(60), remote: twin, device: "copied"), "this Mac's own last upload")
        precondition(!SettingsFile.copiedDevice(local: real.addingTimeInterval(120), remote: twin, device: "copied"), "this Mac's own file from before its latest change")
        precondition(!SettingsFile.copiedDevice(local: .distantPast, remote: twin, device: "copied"), "right after sync is turned on, most likely this Mac's own file from before")
        precondition(!SettingsFile.copiedDevice(local: real, remote: upload(real.addingTimeInterval(60), from: "other"), device: "copied"))
        precondition(!SettingsFile.copiedDevice(local: real, remote: nil, device: "copied"))

        struct Mac { var device: String, modified: Date, pet: Bool }
        var cloud: SettingsFile?
        var uploads = 0
        func exchange(_ mac: inout Mac) {
            if SettingsFile.copiedDevice(local: mac.modified, remote: cloud, device: mac.device) { mac.device = UUID().uuidString }
            switch SettingsFile.merge(local: mac.modified, remote: cloud, device: mac.device) {
            case .apply:
                mac.pet = cloud!.settings[ToolID.pet] as! Bool
                mac.modified = cloud!.modified
            case .upload:
                cloud = SettingsFile(settings: [ToolID.pet: mac.pet], modified: mac.modified, device: mac.device)
                uploads += 1
            case .none:
                break
            }
        }
        var a = Mac(device: "copied", modified: real, pet: false), b = a
        b.pet = true
        b.modified = real.addingTimeInterval(60)
        exchange(&b)
        for _ in 1...3 { exchange(&a); exchange(&b) }
        precondition(a.pet && b.pet && a.device != b.device && uploads == 1, "two Macs with one id overwrite each other: \(uploads) uploads")
        a.pet = false
        a.modified = real.addingTimeInterval(120)
        exchange(&a)
        for _ in 1...3 { exchange(&b); exchange(&a) }
        precondition(!a.pet && !b.pet && uploads == 2, "a change on the other Mac travels back: \(uploads) uploads")
        print("two Macs with one copied device id pass changes on instead of overwriting each other: ok")

        func received(_ root: [String: Any]) -> SettingsFile {
            let header: [String: Any] = ["app": SettingsFile.app, "modified": 1, "device": "old-mac"]
            return SettingsFile(data: try! JSONSerialization.data(withJSONObject: root.merging(header) { value, _ in value }))!
        }
        let legacy = received(["settings": [ToolID.pet: true]])
        precondition(legacy.removed == SettingsFile.keys.intersection(SettingsFile.olderKeys).subtracting([ToolID.pet]), "a file from 1.56.1 or older removes only keys 1.53.1 synced")
        let older = received(["settings": [ToolID.pet: true], "keys": [ToolID.pet, PreferenceKey.petTalks, "retired-key"]])
        precondition(older.removed == [PreferenceKey.petTalks], "a file from a version with fewer keys removes only keys that version knew: \(older.removed)")
        let written = SettingsFile(data: try! SettingsFile(settings: [ToolID.pet: true], modified: real, device: "this-mac").data())!
        precondition(written.known == SettingsFile.keys && written.removed == SettingsFile.keys.subtracting([ToolID.pet]), "a file from this version lists every key it syncs, so a setting put back to its default reaches the other Macs")
        print("a file from an older version never removes settings that version doesn't have: ok")
    }
}
