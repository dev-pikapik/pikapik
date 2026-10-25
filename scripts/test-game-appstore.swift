import CoreGraphics
import Foundation

@main
enum TestGameAppStore {
    static func main() {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("test-game-appstore-\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: suite)!
        let standard: @convention(block) (AnyObject) -> UserDefaults = { _ in defaults }
        method_setImplementation(class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))!, imp_implementationWithBlock(standard))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(atPath: suite + ".plist")
        }
        precondition(UserDefaults.standard === defaults, "the test keeps its settings in a temporary folder")

        let before = GameModeTool.screenLocked
        GameModeTool.shared.received("com.apple.screenIsLocked")
        #if APPSTORE
        precondition(GameModeTool.screenLocked)
        #endif
        precondition(!GameModeTool.shared.isPlaying)
        GameModeTool.shared.received("com.apple.screenIsUnlocked")
        precondition(GameModeTool.screenLocked == before)
        print("lock: ok")
        UserDefaults.standard.set([Int](), forKey: HotKeyTrace.key)
        GameModeTool.shared.games = GameModeTool.shared.games
        precondition(UserDefaults.standard.object(forKey: HotKeyTrace.key) != nil && !GameModeTool.shared.isPlaying, "switching apps without a game leaves Dock settings and shortcuts alone")
        print("app switch without a game: ok")
    }
}
