import AppKit

let args = CommandLine.arguments
guard args.count == 2, let bundle = Bundle(url: URL(fileURLWithPath: args[1])), let executable = bundle.executableURL else {
    print("Usage: smoke-test <app>")
    exit(2)
}
let name = bundle.bundleURL.lastPathComponent
let process = Process()

func fail(_ text: String) -> Never {
    print("::error::\(name) \(text)")
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    exit(1)
}

func within(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if done() { return true }
        let next = Date().addingTimeInterval(0.5)
        RunLoop.current.run(until: next)
        Thread.sleep(until: next)
    }
    return done()
}

func ending() -> String {
    process.terminationReason == .uncaughtSignal ? "signal \(process.terminationStatus)" : "exit status \(process.terminationStatus)"
}

process.executableURL = executable
process.arguments = ["-open-at-login", "<false/>"]
do { try process.run() } catch { fail("did not start: \(error.localizedDescription)") }

var found: NSRunningApplication?
let launched = within(60) {
    found = NSRunningApplication(processIdentifier: process.processIdentifier)
    return !process.isRunning || found?.isFinishedLaunching == true
}
guard process.isRunning else { fail("stopped while starting (\(ending()))") }
guard launched, let app = found else { fail("did not finish starting within 60 s") }
if within(15, { !process.isRunning }) { fail("stopped by itself after starting (\(ending()))") }
guard app.terminate() else { fail("could not be asked to quit") }
guard within(30, { !process.isRunning }) else { fail("did not quit within 30 s of being asked") }
guard process.terminationReason == .exit, process.terminationStatus == 0 else { fail("quit with \(ending())") }
print("\(name) started, kept running for 15 s and quit cleanly")
