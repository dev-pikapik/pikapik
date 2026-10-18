import Foundation

/// A thread with a run loop of its own, for work that must stay off the main thread but needs run loop sources, such as
/// Accessibility observers. The blocks given to `run` execute on it one at a time, in the order they were given.
final class RunLoopThread {
    private var loop: CFRunLoop?

    init(name: String) {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            loop = CFRunLoopGetCurrent()
            // A run loop without a source returns at once; this port never fires and keeps it running.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }

    func run(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(loop)
    }
}
