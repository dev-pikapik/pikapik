import CoreGraphics
import Foundation

@main
struct TestDockDisplay {
    static func plan(_ on: Bool, _ current: Bool?, owned: Bool = false, before: Bool? = nil) -> (Bool?, Bool?, Bool) {
        let result = DockDisplaySwitch.plan(on: on, current: current, owned: owned, before: before)
        return (result.value, result.before, result.restart)
    }

    static func main() {
        precondition(plan(true, nil) == (false, nil, true))
        precondition(plan(true, true) == (false, true, true))
        precondition(plan(true, false) == (false, false, false))
        print("turning on remembers the old value and restarts the Dock only when it changes: ok")

        precondition(plan(false, false, owned: true, before: nil) == (nil, nil, true))
        precondition(plan(false, false, owned: true, before: true) == (true, nil, true))
        precondition(plan(false, false, owned: true, before: false) == (false, nil, false))
        print("turning off puts back exactly what was there: ok")

        precondition(plan(true, false, owned: true, before: nil) == (false, nil, false))
        precondition(plan(true, nil, owned: true, before: nil) == (false, nil, true))
        precondition(plan(true, true, owned: true, before: false) == (false, false, true))
        print("on: a key someone removed or changed is written again: ok")

        precondition(plan(false, nil) == (nil, nil, false))
        precondition(plan(false, false) == (false, nil, false))
        precondition(plan(false, true) == (true, nil, false))
        precondition(plan(false, nil, owned: true, before: true) == (nil, nil, false))
        precondition(plan(false, true, owned: true, before: nil) == (true, nil, false))
        precondition(plan(false, true, owned: true, before: false) == (true, nil, false))
        print("off: the key is left alone unless pikapik set it, and the Dock restarts only on a real change: ok")

        let crashed = DockDisplaySwitch.plan(on: true, current: true, owned: false, before: nil)
        let again = DockDisplaySwitch.plan(on: true, current: crashed.value, owned: true, before: crashed.before)
        precondition(again.value == false && again.before == true && !again.restart)
        let off = DockDisplaySwitch.plan(on: false, current: crashed.value, owned: true, before: again.before)
        precondition(off.value == true && off.restart)
        print("after a crash the next launch keeps the real value as the original and puts it back: ok")

        let defaults = UserDefaults.standard
        [DockDisplaySwitch.ownedKey, DockDisplaySwitch.beforeKey].forEach(defaults.removeObject)
        var written: Bool??
        precondition(DockDisplaySwitch.apply(true, current: true) { value in
            precondition(defaults.bool(forKey: DockDisplaySwitch.ownedKey) && defaults.object(forKey: DockDisplaySwitch.beforeKey) as? Bool == true)
            written = value
        })
        precondition(written == false && defaults.bool(forKey: DockDisplaySwitch.ownedKey))
        precondition(DockDisplaySwitch.apply(false, current: false) { value in
            precondition(defaults.bool(forKey: DockDisplaySwitch.ownedKey) && defaults.object(forKey: DockDisplaySwitch.beforeKey) as? Bool == true)
            written = value
        })
        precondition(written == true && !defaults.bool(forKey: DockDisplaySwitch.ownedKey) && defaults.object(forKey: DockDisplaySwitch.beforeKey) == nil)
        print("the old value is saved before the Dock key is written and forgotten only after it is put back: ok")

        let side = ["a": CGPoint(x: 0, y: 0), "b": CGPoint(x: 1920, y: -120), "c": CGPoint(x: -1440, y: 60)]
        let moved = MainDisplay.moved(side, to: "b")
        precondition(moved == ["a": CGPoint(x: -1920, y: 120), "b": .zero, "c": CGPoint(x: -3360, y: 180)])
        precondition(MainDisplay.moved(side, to: "a") == nil && MainDisplay.moved(side, to: "z") == nil)
        print("making a display the main one shifts every display by the same amount, so the arrangement keeps its shape: ok")

        precondition(MainDisplay.origins([("a", CGPoint.zero), ("b", CGPoint(x: 1920, y: 0))]) == ["a": .zero, "b": CGPoint(x: 1920, y: 0)])
        precondition(MainDisplay.origins([("a", CGPoint.zero), ("a", CGPoint(x: 1920, y: 0))]) == nil)
        print("two displays with the same UUID are left alone instead of crashing pikapik: ok")

        typealias Saved = MainDisplay.Saved
        let home = ["a": CGPoint.zero, "d": CGPoint(x: 1512, y: -300)]
        var journal = MainDisplay.remembered([:], now: side, main: "b")
        precondition(journal == [MainDisplay.set(side): Saved(origins: side, main: "b")])
        journal = MainDisplay.remembered(journal, now: moved!, main: "c")
        precondition(journal == [MainDisplay.set(side): Saved(origins: side, main: "c")])
        journal = MainDisplay.remembered(journal, now: home, main: "d")
        precondition(journal == [MainDisplay.set(side): Saved(origins: side, main: "c"), MainDisplay.set(home): Saved(origins: home, main: "d")])
        precondition(MainDisplay.set(["b": .zero, "a": .zero]) == MainDisplay.set(["a": .zero, "b": .zero]))
        print("each set of displays keeps its own first arrangement, and a later pick only changes which display pikapik made the main one: ok")

        let picked = [MainDisplay.set(side): Saved(origins: side, main: "b")]
        let back = MainDisplay.restored(picked, now: moved!)
        precondition(back.write == side && back.journal.isEmpty)
        let same = MainDisplay.restored(picked, now: side)
        precondition(same.write == nil && same.journal.isEmpty)
        let theirs = MainDisplay.restored(picked, now: MainDisplay.moved(side, to: "c")!)
        precondition(theirs.write == nil && theirs.journal.isEmpty)
        precondition(MainDisplay.restored([MainDisplay.set(side): Saved(origins: side, main: nil)], now: MainDisplay.moved(side, to: "c")!).write == side)
        print("restoring writes the old arrangement only when it differs and pikapik's pick is still the main display: ok")

        let away = MainDisplay.restored(picked, now: home)
        precondition(away.write == nil && away.journal == picked)
        let unplugged = MainDisplay.restored(picked, now: ["a": .zero, "b": CGPoint(x: 1920, y: -120)])
        precondition(unplugged.write == nil && unplugged.journal == picked)
        let returned = MainDisplay.restored(unplugged.journal, now: moved!)
        precondition(returned.write == side && returned.journal.isEmpty)
        print("an arrangement saved for displays that aren't connected waits for them instead of being forgotten: ok")

        let both = journal.merging([MainDisplay.set(["x": .zero]): Saved(origins: ["x": .zero], main: nil)]) { kept, _ in kept }
        defaults.set(MainDisplay.stored(both), forKey: "dock-display-arrangements")
        precondition(MainDisplay.journal(defaults.dictionary(forKey: "dock-display-arrangements"), old: nil) == both)
        defaults.removeObject(forKey: "dock-display-arrangements")
        let old = ["a": [0.0, 0.0], "b": [1920.0, -120.0], "c": [-1440.0, 60.0]]
        precondition(MainDisplay.journal(nil, old: old) == [MainDisplay.set(side): Saved(origins: side, main: nil)])
        precondition(MainDisplay.journal(MainDisplay.stored(picked), old: old) == picked)
        precondition(MainDisplay.journal(["junk": 1, "bad": ["origins": ["a": [1.0]]]], old: ["a": [1.0, 2.0, 3.0]]).isEmpty)
        print("the saved arrangements survive UserDefaults, and the one an older version saved is still put back: ok")
    }
}
