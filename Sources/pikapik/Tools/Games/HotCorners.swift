import Foundation

#if !APPSTORE
private let applicationServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

enum HotCorners {
    private static let journalKey = "hot-corners-before", oursKey = "hot-corners-ours"

    static func key(_ side: String) -> String { "wvous-\(side)-corner" }

    static var before: [String: Int] { journal(.system).before }

    static func choose(_ action: Int, current: Int, saved: [String: Int], side: String) -> (saved: [String: Int], write: Int?) {
        guard action != current else { return (saved, nil) }
        var saved = saved
        if saved[side] == nil { saved[side] = current }
        return (saved, action)
    }

    static var ours: [String: Int] { journal(.system).ours }

    static func putBack(current: Int, saved: [String: Int], ours: Int? = nil, side: String) -> (saved: [String: Int], write: Int?) {
        var saved = saved
        guard let original = saved.removeValue(forKey: side) else { return (saved, nil) }
        guard ours.map({ $0 == current }) ?? true else { return (saved, nil) }
        return (saved, original == current ? nil : original)
    }

    static func choose(_ action: Int, side: String, _ host: DockHost = .system) {
        apply(side, choose(action, current: current(side, host), saved: journal(host).before, side: side), host) { put($0, side: side, host) }
    }

    static func putBack(side: String, _ host: DockHost = .system) {
        apply(side, putBack(current: current(side, host), saved: journal(host).before, side: side), host) { put($0, side: side, host) }
    }

    static func putBackAll(_ host: DockHost = .system) {
        var saved = journal(host).before, wrote: [String: Int] = [:]
        let ours = journal(host).ours
        for side in saved.keys {
            let plan = putBack(current: current(side, host), saved: saved, ours: ours[side], side: side)
            saved = plan.saved
            guard let value = plan.write, DockEdges.write(key(side), value, host) else { continue }
            wrote[key(side)] = value
        }
        if !wrote.isEmpty, !host.setCorners(wrote) { host.relaunch() }
        remember(saved, [:], host)
    }

    static func kept(_ old: [String: Int], _ new: [String: Int]) -> [String: Int] {
        old.merging(new) { $1 }
    }

    static func apply(_ side: String, _ result: (saved: [String: Int], write: Int?), _ host: DockHost = .system, write: (Int) -> Void) {
        let now = journal(host)
        var written = now.ours
        written[side] = result.saved[side] == nil ? nil : (result.write ?? written[side])
        remember(kept(now.before, result.saved), kept(now.ours, written), host)
        if let value = result.write { write(value) }
        remember(result.saved, written, host)
    }

    private static func journal(_ host: DockHost) -> (before: [String: Int], ours: [String: Int]) {
        (host.journal.dictionary(forKey: journalKey) as? [String: Int] ?? [:], host.journal.dictionary(forKey: oursKey) as? [String: Int] ?? [:])
    }

    private static func current(_ side: String, _ host: DockHost) -> Int {
        (DockEdges.read(key(side), host) as? NSNumber)?.intValue ?? 0
    }

    private static func put(_ value: Int, side: String, _ host: DockHost) {
        guard DockEdges.write(key(side), value, host), !host.setCorners([key(side): value]) else { return }
        host.relaunch()
    }

    private static func remember(_ saved: [String: Int], _ ours: [String: Int], _ host: DockHost) {
        host.journal.set(saved.isEmpty ? nil : saved, forKey: journalKey)
        host.journal.set(ours.isEmpty ? nil : ours, forKey: oursKey)
    }
}

enum DockCorners {
    private typealias Read = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias Write = @convention(c) (Int32, Int32, Int32) -> Int32

    private static let library = dlopen(applicationServicesPath, RTLD_LAZY)
    private static let read = dlsym(library, "CoreDockGetExposeCornerActionsWithModifiers").map { unsafeBitCast($0, to: Read.self) }
    private static let write = dlsym(library, "CoreDockSetExposeCornerActionWithModifier").map { unsafeBitCast($0, to: Write.self) }
    static let names = ["tl", "tr", "bl", "br"].map(HotCorners.key)

    static func set(_ actions: [String: Int]) -> Bool {
        guard !actions.isEmpty else { return true }
        guard let write, let now = current() else { return false }
        for (name, action) in actions {
            guard let corner = names.firstIndex(of: name), write(Int32(max(action, 1)), Int32(corner), now.modifiers[corner]) == 0 else { return false }
        }
        return current().map { same(actions, $0.actions) } ?? false
    }

    static func same(_ wanted: [String: Int], _ actions: [Int32]) -> Bool {
        wanted.allSatisfy { name, action in names.firstIndex(of: name).map { max(Int(actions[$0]), 1) == max(action, 1) } ?? false }
    }

    private static func current() -> (actions: [Int32], modifiers: [Int32])? {
        guard let read else { return nil }
        var actions = [Int32](repeating: 0, count: 4), modifiers = [Int32](repeating: 0, count: 4)
        return read(&actions, &modifiers) == 0 ? (actions, modifiers) : nil
    }
}
#endif
