#if !APPSTORE
import Foundation

struct PointerMouse {
    let id: String
    let written: [String: Int]
    let read: (Set<String>) -> [String: Int]
    let write: (String, Int) -> Void
}

enum PointerPutBack {
    typealias Saved = [String: [String: Int]]
    typealias Ours = [String: [String: [Int]]]

    static let linearKey = "HIDUseLinearScalingMouseAcceleration"

    static func load(_ journal: UserDefaults) -> (saved: Saved, ours: Ours) {
        (journal.dictionary(forKey: PreferenceKey.linearPointerSaved) as? Saved ?? [:], journal.dictionary(forKey: PreferenceKey.linearPointerOurs) as? Ours ?? [:])
    }

    static func save(_ saved: Saved, _ ours: Ours, to journal: UserDefaults) {
        journal.set(saved.isEmpty ? nil : saved, forKey: PreferenceKey.linearPointerSaved)
        journal.set(ours.isEmpty ? nil : ours, forKey: PreferenceKey.linearPointerOurs)
    }

    static func run(_ mice: [PointerMouse], saved: Saved, ours: Ours, system: (Set<String>) -> [String: Int]) -> (saved: Saved, ours: Ours) {
        var left: Saved = [:]
        for mouse in mice {
            guard let before = saved[mouse.id] else { continue }
            let mine = ours[mouse.id] ?? mouse.written.mapValues { [$0] }
            let goal = OriginalValue.goal(saved: before, system: system(Set(before.keys).union(mine.keys).union([linearKey])), unset: [linearKey: 0])
            for (key, value) in OriginalValue.putBack(goal, ours: mine, current: mouse.read(Set(goal.keys))) {
                mouse.write(key, value)
            }
            if !OriginalValue.isBack(goal, ours: mine, current: mouse.read(Set(goal.keys))) { left[mouse.id] = before }
        }
        return (left, ours.filter { left[$0.key] != nil })
    }
}
#endif
