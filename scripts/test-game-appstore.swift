import CoreGraphics
import Foundation

@main
enum TestGameAppStore {
    static func main() {
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
        [HotKeyTrace.key, PreferenceKey.gameModeGames].forEach(UserDefaults.standard.removeObject)
        print("app switch without a game: ok")
    }
}
