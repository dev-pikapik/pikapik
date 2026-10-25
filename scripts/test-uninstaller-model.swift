import AppKit

enum Permission {
    case fullDisk
}

final class Permissions {
    static let shared = Permissions()
    let fileAccess = true

    func ask(_ missing: [Permission]) {}
}

enum SettingsTab {
    case uninstaller
}

enum SettingsWindow {
    static func show(_ tab: SettingsTab? = nil) {}
}

extension AppRemover {
    static func live(footprint: AppFootprint, confirmQuit: @escaping ([String]) async -> Bool, confirmForceQuit: @escaping ([String]) async -> Bool) -> AppRemover {
        let hooks = AppRemover.Hooks(running: { _ in [] }, confirmQuit: { _ in false }, confirmForceQuit: { _ in false }, launchctl: { _ in 1 },
                                     admin: { _, _ in .failed }, finder: { _ in .failed }, forget: { _ in })
        let home = footprint.roots.home
        return AppRemover(footprint: footprint, hooks: hooks, store: home.deletingLastPathComponent().appendingPathComponent("store"), trash: home.appendingPathComponent(".Trash"))
    }
}

final class Tally {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func add() { lock.withLock { value += 1 } }
}

final class World {
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pika-uninstaller-model-\(UUID().uuidString)")
    private let fm = FileManager.default

    init() {
        for name in ["root/Applications", "home/.Trash", "cache", "temp", "store"] { folder(name) }
    }

    func at(_ path: String) -> URL { base.appendingPathComponent(path) }

    func folder(_ path: String) {
        try! fm.createDirectory(at: at(path), withIntermediateDirectories: true)
    }

    func app(_ name: String, id: String, folders: Int) -> AppIdentity {
        let bundle = "root/Applications/\(name).app"
        folder(bundle + "/Contents/MacOS")
        try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": name], format: .xml, options: 0)
            .write(to: at(bundle + "/Contents/Info.plist"))
        try! "x".write(to: at(bundle + "/Contents/MacOS/" + name), atomically: false, encoding: .utf8)
        for index in 0..<folders { folder("\(bundle)/Contents/Resources/\(index / 100)/\(index)") }
        return AppIdentity.read(at: at(bundle), signed: false)!
    }

    var roots: AppRoots {
        AppRoots(home: at("home"), root: at("root"), userCache: at("cache"), userTemp: at("temp"), caskrooms: [at("root/opt/homebrew/Caskroom")],
                 pkgutil: { _ in nil }, isKnownApp: { _ in false })
    }

    func engine(counting rebuilds: Tally) -> UninstallerEngine {
        let roots = self.roots
        return UninstallerEngine(footprint: {
            rebuilds.add()
            return AppFootprint(roots: roots, running: nil)
        })
    }

    func destroy() {
        try? fm.removeItem(at: base)
    }
}

@main @MainActor
enum UninstallerModelTests {
    static let world = World()
    static var problems: [String] = []

    static func main() async {
        let app = world.app("Stub", id: "com.example.stub", folders: 6_000)
        await pausing()
        await closing(app)
        await dismissing(app)
        await offering()
        await reloading()
        await drawing(app)
        await lookingAgain()
        await flattening()
        world.destroy()
        precondition(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
        print("uninstaller model: pause, close and dismissing the sheet stop a long size walk, Trash bursts and reloads build the app list once, icons are drawn off the main thread: ok")
    }

    static func pausing() async {
        let model = UninstallerModel(engine: world.engine(counting: Tally()))
        let entries = slowWalk()
        model.reload()
        let started = await wait { entries.count >= 200 }
        let before = entries.count
        let took = await seconds { await model.pause() }
        let walked = entries.count - before
        AppFootprint.onEntry = nil
        check(started, "reload() never reached the size walk")
        check(walked < 2_000 && took < 1, "the size walk read \(walked) more entries (\(String(format: "%.2f", took)) s) after pause(), at most 2000 and 1 s")
    }

    static func closing(_ app: AppIdentity) async {
        let model = UninstallerModel(engine: world.engine(counting: Tally()))
        let entries = slowWalk()
        model.open(app)
        let started = await wait { entries.count >= 200 }
        let work = model.session?.work
        let before = entries.count
        model.close()
        let took = await seconds { await work?.value }
        let walked = entries.count - before
        AppFootprint.onEntry = nil
        check(started, "open() never reached the size walk")
        check(walked < 2_000 && took < 1, "the size walk read \(walked) more entries (\(String(format: "%.2f", took)) s) after close(), at most 2000 and 1 s")
    }

    static func dismissing(_ app: AppIdentity) async {
        let model = UninstallerModel(engine: world.engine(counting: Tally()))
        var entries = slowWalk()
        model.open(app)
        let started = await wait { entries.count >= 200 }
        let work = model.session?.work
        let before = entries.count
        model.session = nil
        await work?.value
        let walked = entries.count - before
        check(started, "open() never reached the size walk")
        check(walked < 2_000, "the size walk read \(walked) more entries after the sheet was dismissed, at most 2000")
        entries = slowWalk()
        model.open(app)
        _ = await wait { entries.count >= 200 }
        model.session?.phase = .removing
        let busy = model.session?.work
        model.session = nil
        check(busy?.isCancelled == false, "dismissing the sheet during a removal stopped the removal")
        busy?.cancel()
        await busy?.value
        AppFootprint.onEntry = nil
    }

    static func offering() async {
        let rebuilds = Tally()
        let model = UninstallerModel(engine: world.engine(counting: rebuilds))
        let trash = world.at("home/.Trash")
        model.offer([trash.appendingPathComponent("Gone 1.app")])
        let first = await wait { rebuilds.count >= 1 }
        for index in 2...10 { model.offer([trash.appendingPathComponent("Gone \(index).app")]) }
        let drained = await wait { !model.draining }
        check(first && drained, "offer() never finished checking the Trash")
        check(rebuilds.count <= 2, "10 apps moved to the Trash built the app list \(rebuilds.count) times, at most 2")
    }

    static func reloading() async {
        let rebuilds = Tally()
        let model = UninstallerModel(engine: world.engine(counting: rebuilds))
        for _ in 1...10 { model.reload() }
        let loaded = await wait { model.loaded }
        await model.pause()
        check(loaded, "reload() never loaded the app list")
        check(rebuilds.count <= 2, "10 reload() calls in a row built the app list \(rebuilds.count) times, at most 2")
    }

    static func drawing(_ app: AppIdentity) async {
        let draws = Tally()
        let onMain = Tally()
        let gate = DispatchSemaphore(value: 0)
        let drawn = NSImage()
        let model = UninstallerModel(engine: world.engine(counting: Tally())) { _, _ in
            if Thread.isMainThread { onMain.add() }
            _ = gate.wait(timeout: .now() + 1)
            draws.add()
            return drawn
        }
        let took = await seconds { _ = model.icon(of: app) }
        gate.signal()
        let arrived = await wait { model.icon(of: app) === drawn }
        for _ in 1...10 { _ = model.icon(at: app.url) }
        check(took < 0.5 && onMain.count == 0, "the app’s icon was drawn on the main thread and froze the window for \(String(format: "%.2f", took)) s")
        check(arrived, "the app’s icon never replaced the placeholder")
        check(draws.count == 1, "the same icon was drawn \(draws.count) times, once is enough")
    }

    static func lookingAgain() async {
        let looks = Tally()
        let model = UninstallerModel(engine: world.engine(counting: Tally())) { _, _ in
            looks.add()
            return nil
        }
        let gone = AppIdentity(url: world.at("root/Applications/Gone.app"), bundleID: "")
        let redraws = Tally()
        withObservationTracking { _ = model.icon(of: gone) } onChange: { redraws.add() }
        let again = await wait {
            _ = model.icon(of: gone)
            return looks.count >= 2
        }
        check(again, "an app that wasn’t there was never looked for again")
        check(redraws.count == 0, "not finding an app redrew the page, which would look for it again and again")
    }

    static func flattening() async {
        let file = world.at("Red.txt")
        try! "x".write(to: file, atomically: false, encoding: .utf8)
        let red = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        guard NSWorkspace.shared.setIcon(red, forFile: file.path, options: []) else { return }
        let icon = await Task.detached { UninstallerModel.picture(at: file.path, app: false) }.value
        try! FileManager.default.removeItem(at: file)
        check(icon.map(isRed) == true, "an icon drawn off the main thread still read its file when it was shown")
    }

    static func isRed(_ image: NSImage) -> Bool {
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pixels)
        image.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40))
        NSGraphicsContext.restoreGraphicsState()
        let middle = pixels.colorAt(x: 20, y: 20)!
        return middle.redComponent > 0.8 && middle.greenComponent < 0.2
    }

    static func slowWalk() -> Tally {
        let entries = Tally()
        AppFootprint.onEntry = {
            usleep(100)
            entries.add()
        }
        return entries
    }

    static func wait(until done: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !done() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    static func seconds(_ work: () async -> Void) async -> TimeInterval {
        let start = Date()
        await work()
        return Date().timeIntervalSince(start)
    }

    static func check(_ passed: Bool, _ problem: String) {
        if !passed { problems.append(problem) }
    }
}
