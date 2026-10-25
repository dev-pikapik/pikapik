import Foundation

final class PretendMouse {
    let id: String
    var values: [String: Int]
    var accepts = true
    var writes: [(key: String, value: Int)] = []

    init(_ values: [String: Int], id: String = "mouse") {
        self.values = values
        self.id = id
    }

    var pointer: PointerMouse {
        PointerMouse(id: id, written: TestPointerPutBack.written, read: { keys in self.values.filter { keys.contains($0.key) } }, write: { key, value in
            guard self.accepts else { return }
            self.values[key] = value
            self.writes.append((key, value))
        })
    }

    func wrote(_ expected: [String: Int]) -> Bool {
        writes.count == expected.count && writes.allSatisfy { expected[$0.key] == $0.value }
    }
}

@main
struct TestPointerPutBack {
    static let linear = PointerPutBack.linearKey
    static let before = ["HIDMouseAcceleration": 45056, "HIDPointerResolution": 26214400]
    static let ours = [linear: [1], "HIDMouseAcceleration": [78643]]
    static let current = [linear: 1, "HIDMouseAcceleration": 78643, "HIDPointerResolution": 26214400]
    static let written = [linear: 1, "HIDMouseAcceleration": 78643]

    static func main() {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("test-pointer-put-back-\(UUID().uuidString)").path
        let journal = UserDefaults(suiteName: suite)!

        PointerPutBack.save(["mouse": before], ["mouse": ours], to: journal)
        var notes = PointerPutBack.load(UserDefaults(suiteName: suite)!)
        precondition(notes.saved == ["mouse": before] && notes.ours == ["mouse": ours])
        var mouse = PretendMouse(current)
        notes = PointerPutBack.run([mouse.pointer], saved: notes.saved, ours: notes.ours) { _ in [:] }
        precondition(mouse.wrote([linear: 0, "HIDMouseAcceleration": 45056]) && notes.saved.isEmpty && notes.ours.isEmpty)
        PointerPutBack.save(notes.saved, notes.ours, to: journal)
        precondition(journal.object(forKey: PreferenceKey.linearPointerSaved) == nil && journal.object(forKey: PreferenceKey.linearPointerOurs) == nil)
        print("--uninstall in a new copy puts back what the notes hold and clears them: ok")

        mouse = PretendMouse(current)
        notes = PointerPutBack.run([mouse.pointer], saved: ["mouse": before], ours: ["mouse": ours]) { _ in ["HIDMouseAcceleration": 32768] }
        precondition(mouse.wrote([linear: 0, "HIDMouseAcceleration": 32768]) && notes.saved.isEmpty && notes.ours.isEmpty)
        print("what System Settings has now wins over what the mouse had: ok")

        mouse = PretendMouse(current.merging(["HIDMouseAcceleration": 60000]) { $1 })
        notes = PointerPutBack.run([mouse.pointer], saved: ["mouse": before], ours: ["mouse": ours]) { _ in [:] }
        precondition(mouse.wrote([linear: 0]) && notes.saved.isEmpty && notes.ours.isEmpty)
        print("a speed changed by hand since stays, the rest goes back and the mouse is forgotten: ok")

        mouse = PretendMouse(current)
        mouse.accepts = false
        notes = PointerPutBack.run([mouse.pointer], saved: ["mouse": before], ours: ["mouse": ours]) { _ in [:] }
        precondition(mouse.values == current && notes.saved == ["mouse": before] && notes.ours == ["mouse": ours])
        PointerPutBack.save(notes.saved, notes.ours, to: journal)
        notes = PointerPutBack.load(UserDefaults(suiteName: suite)!)
        precondition(notes.saved == ["mouse": before] && notes.ours == ["mouse": ours])
        print("a mouse that doesn't take the values keeps its notes for the next try: ok")

        mouse = PretendMouse(current, id: "other")
        notes = PointerPutBack.run([mouse.pointer], saved: ["mouse": before], ours: ["mouse": ours]) { _ in [:] }
        precondition(mouse.writes.isEmpty && notes.saved.isEmpty && notes.ours.isEmpty)
        print("a mouse that is gone is forgotten and one pikapik never changed is left alone: ok")

        mouse = PretendMouse(current)
        notes = PointerPutBack.run([mouse.pointer], saved: ["mouse": before], ours: [:]) { _ in [:] }
        precondition(mouse.wrote([linear: 0, "HIDMouseAcceleration": 45056]) && notes.saved.isEmpty && notes.ours.isEmpty)
        print("without notes of its own values, what pikapik writes now counts as its own: ok")

        journal.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}
