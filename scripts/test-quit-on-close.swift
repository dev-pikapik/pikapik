import CoreGraphics
import Foundation

@main
enum TestQuitOnClose {
    static func window(_ pid: pid_t, _ frame: CGRect, layer: Int = 0, alpha: Double = 1, owner: String = "App") -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
            kCGWindowOwnerName as String: owner, kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]
    }

    static func main() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let app = [window(42, frame)]
        precondition(TitleBarCorner.owner(at: CGPoint(x: 112, y: 112), in: app, except: 1) == 42, "a click on the close button belongs to the window's app")
        precondition(TitleBarCorner.owner(at: CGPoint(x: 885, y: 112), in: app, except: 1) == 42, "in right-to-left languages the buttons sit top right")
        precondition(TitleBarCorner.owner(at: CGPoint(x: 112, y: 150), in: app, except: 1) == 42, "a window with a toolbar has its buttons lower")
        for point in [CGPoint(x: 500, y: 112), CGPoint(x: 112, y: 400), CGPoint(x: 50, y: 112)] {
            precondition(TitleBarCorner.owner(at: point, in: app, except: 1) == nil, "a click away from the corners is not looked at: \(point)")
        }
        print("only a click in a title bar corner is looked at: ok")

        let overlays = [
            window(7, CGRect(x: 0, y: 0, width: 2000, height: 1200), layer: 25, owner: "Overlay"),
            window(8, CGRect(x: 0, y: 0, width: 2000, height: 1200), alpha: 0, owner: "Invisible"),
            window(9, CGRect(x: 0, y: 0, width: 2000, height: 1200), owner: "Dock"),
        ] + app
        precondition(TitleBarCorner.owner(at: CGPoint(x: 112, y: 112), in: overlays, except: 1) == 42, "menus, overlays, invisible windows and the Dock are skipped")
        precondition(TitleBarCorner.owner(at: CGPoint(x: 112, y: 112), in: [window(5, CGRect(x: 0, y: 0, width: 300, height: 300))] + app, except: 1) == nil,
                     "a window in front hides the corner behind it")
        precondition(TitleBarCorner.owner(at: CGPoint(x: 112, y: 112), in: app, except: 42) == nil, "pikapik's own windows are skipped")
        print("the front normal window under the click decides, and pikapik's own windows are skipped: ok")

        let thread = RunLoopThread(name: "test")
        let done = DispatchSemaphore(value: 0)
        var order: [Int] = []
        var loops: [CFRunLoop] = []
        var onMain = false
        for index in 0..<100 {
            thread.run {
                order.append(index)
                loops.append(CFRunLoopGetCurrent())
                onMain = onMain || Thread.isMainThread
                if index == 99 { done.signal() }
            }
        }
        precondition(done.wait(timeout: .now() + 5) == .success, "the thread runs what it is given")
        precondition(order == Array(0..<100), "one at a time, in the order given: \(order)")
        precondition(!onMain && loops.allSatisfy { $0 === loops[0] }, "on one thread that is not the main one")
        print("the observing thread runs its work in order, off the main thread: ok")

        let fired = DispatchSemaphore(value: 0)
        var firedOffMain = false
        thread.run {
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.05, 0, 0, 0) { _ in
                firedOffMain = !Thread.isMainThread
                fired.signal()
            }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        }
        precondition(fired.wait(timeout: .now() + 5) == .success && firedOffMain, "a run loop source added on the thread fires there")
        print("a source added on the observing thread, such as an app's window news, fires there: ok")

        let answered = DispatchSemaphore(value: 0)
        let asked = Date()
        var answer = Date.distantFuture
        thread.run { answer = Date(); answered.signal() }
        Thread.sleep(forTimeInterval: 1)
        precondition(answered.wait(timeout: .now() + 5) == .success && answer.timeIntervalSince(asked) < 0.9, "the thread must not wait for a busy main thread")
        print("the observing thread works while the main thread is busy: ok")
    }
}
