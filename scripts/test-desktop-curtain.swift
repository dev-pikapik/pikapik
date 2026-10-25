import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FolderAccess {
    static var reopened = 0

    static func reopen() -> Bool {
        reopened += 1
        return true
    }
}

final class Probe: NSWindow {
    var calls: [String] = []
    override func orderBack(_ sender: Any?) { calls.append("orderBack") }
    override func orderFront(_ sender: Any?) { calls.append("orderFront") }
    override func orderFrontRegardless() { calls.append("orderFrontRegardless") }
    override func makeKeyAndOrderFront(_ sender: Any?) { calls.append("makeKeyAndOrderFront") }
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) { calls.append("order") }
}

@main
struct TestDesktopCurtain {
    static func picture(_ frames: [(Int, Int)], type: UTType = .tiff, _ tag: String? = nil, _ value: String = "") -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, frames.count, nil)!
        let metadata = CGImageMetadataCreateMutable()
        if let tag {
            precondition(CGImageMetadataRegisterNamespaceForPrefix(metadata, "http://ns.apple.com/namespace/1.0/" as CFString, "apple_desktop" as CFString, nil))
            precondition(CGImageMetadataSetValueWithPath(metadata, nil, "apple_desktop:\(tag)" as CFString, value as CFString))
        }
        for (width, height) in frames {
            let image = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func wallpaper(_ tag: String? = nil, _ value: String = "") -> CGImageSource {
        let source = CGImageSourceCreateWithData(picture([(1, 1), (1, 1)], tag, value) as CFData, nil)!
        precondition(CGImageSourceGetCount(source) == 2)
        return source
    }

    static func list(_ object: [String: Any]) -> String {
        try! PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).base64EncodedString()
    }

    static func main() {
        let plain = wallpaper()
        precondition(WallpaperFrame.index(plain, dark: false) == 0)
        precondition(WallpaperFrame.index(plain, dark: true) == 0)
        print("a wallpaper without light and dark frames shows its first frame: ok")

        let flipped = wallpaper("apr", list(["l": 1, "d": 0]))
        precondition(WallpaperFrame.index(flipped, dark: false) == 1)
        precondition(WallpaperFrame.index(flipped, dark: true) == 0)
        print("light and dark take the frames the wallpaper names for them: ok")

        let solar = wallpaper("solar", list(["ap": ["l": 0, "d": 1], "si": [["a": 10, "i": 0, "z": 100], ["a": -25, "i": 1, "z": 70]]]))
        precondition(WallpaperFrame.index(solar, dark: false) == 0)
        precondition(WallpaperFrame.index(solar, dark: true) == 1)
        print("a wallpaper that follows the sun takes its light and dark frames too: ok")

        let day = wallpaper("h24", list(["ap": ["l": 1, "d": 0], "ti": [["i": 1, "t": 0.3], ["i": 0, "t": 0.8]]]))
        precondition(WallpaperFrame.index(day, dark: false) == 1)
        precondition(WallpaperFrame.index(day, dark: true) == 0)
        print("a wallpaper that follows the time of day takes its light and dark frames too: ok")

        for broken in [wallpaper("apr", list(["l": 0, "d": 2])), wallpaper("apr", "not a list"), wallpaper("solar", list(["si": [["a": 10, "i": 1, "z": 100]]]))] {
            precondition(WallpaperFrame.index(broken, dark: false) == 0)
            precondition(WallpaperFrame.index(broken, dark: true) == 0)
        }
        print("a frame that isn't there or unreadable metadata falls back to the first frame: ok")

        let aqua = NSAppearance(named: .aqua)!, darkAqua = NSAppearance(named: .darkAqua)!
        for system in [nil, "Dark"] {
            precondition(!WallpaperFrame.dark(own: nil, effective: aqua, system: system))
            precondition(WallpaperFrame.dark(own: nil, effective: darkAqua, system: system))
        }
        print("with Appearance on System the curtain follows pikapik's look, whatever the system key says: ok")

        precondition(!WallpaperFrame.dark(own: darkAqua, effective: darkAqua, system: nil))
        print("pikapik set to Dark while macOS is light shows the light frame: ok")

        precondition(WallpaperFrame.dark(own: aqua, effective: aqua, system: "Dark"))
        print("pikapik set to Light while macOS is dark shows the dark frame: ok")

        _ = NSApplication.shared
        NSApp.appearance = aqua
        func system(_ look: String) {
            UserDefaults.standard.setVolatileDomain(["AppleInterfaceStyle": look], forName: UserDefaults.argumentDomain)
        }
        system("Light")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("test-desktop-curtain-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ name: String, _ data: Data) -> URL {
            let url = folder.appendingPathComponent(name)
            try! data.write(to: url)
            return url
        }
        let photo = file("photo.png", picture([(4, 3)], type: .png)), other = file("other.png", picture([(3, 4)], type: .png))
        let moving = file("DefaultDesktop.heic", picture([(4, 3)], type: .png)), broken = file("broken.heic", Data("not a picture".utf8))
        let big = file("big.png", picture([(6000, 4000)], type: .png))
        let look = file("look.tiff", picture([(1, 1), (2, 2)], "apr", list(["l": 1, "d": 0])))
        precondition(CGImageSourceCreateWithURL(moving as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil)

        func screen(_ frame: CGRect, _ url: URL?, scale: CGFloat = 1, _ options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]) -> DesktopCurtain.Screen {
            DesktopCurtain.Screen(frame: frame, scale: scale, url: url, options: options)
        }
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900), right = CGRect(x: 1440, y: -180, width: 2560, height: 1440)
        var screens = [screen(left, photo, scale: 2), screen(right, photo)]
        var asked = 0
        var shown: [NSWindow] = []
        let orderBack = DesktopCurtain.show
        DesktopCurtain.screens = {
            asked += 1
            return screens
        }
        DesktopCurtain.show = { shown.append($0) }
        func drawn(_ change: () -> Void) -> [NSWindow] {
            shown = []
            autoreleasepool(invoking: change)
            let windows = shown
            shown = []
            return windows
        }
        let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        func curtains() -> Int {
            autoreleasepool { NSApp.windows.filter { $0.level.rawValue == level }.count }
        }
        func notify(_ name: Notification.Name) {
            (name == NSApplication.didChangeScreenParametersNotification ? NotificationCenter.default : NSWorkspace.shared.notificationCenter).post(name: name, object: nil)
        }
        let changes = [NSApplication.didChangeScreenParametersNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification]
        func spin(_ seconds: Double, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done(), Date() < end { _ = RunLoop.current.run(mode: .default, before: end) }
        }
        func image(_ windows: [NSWindow]) -> CGImage? {
            windows.first?.contentView?.layer?.contents.map { $0 as! CGImage }
        }

        let curtain = DesktopCurtain()
        autoreleasepool {
            let first = drawn { curtain.isOn = true }
            precondition(first.map(\.frame) == [left, right] && curtains() == 2, "\(first.map(\.frame))")
            for window in first {
                precondition(window.level.rawValue == level)
                precondition(window.ignoresMouseEvents)
                precondition(window.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .stationary]))
            }
        }
        print("two screens get one curtain each, exactly over the screen and one level above the desktop icons: ok")
        print("clicks go through the curtain to the desktop, and it stays on every Space: ok")

        let probe = autoreleasepool { Probe(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true) }
        orderBack(probe)
        precondition(probe.calls == ["orderBack"], "\(probe.calls)")
        print("a curtain is put in with orderBack, so the pet at the same level stays above it: ok")

        precondition(FolderAccess.reopened > 0)
        print("the curtain opens the saved home folder access before it reads the wallpaper: ok")

        let same = drawn {
            changes.forEach(notify)
            curtain.isOn = true
        }
        precondition(same.isEmpty && curtains() == 2)
        print("a screen, Space or app change with the same wallpapers redraws nothing: ok")

        let third = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        screens.append(screen(third, photo))
        precondition(drawn { notify(NSApplication.didChangeScreenParametersNotification) }.map(\.frame) == [left, right, third] && curtains() == 3)
        screens = [screen(left, photo, scale: 2)]
        precondition(drawn { notify(NSApplication.didChangeScreenParametersNotification) }.map(\.frame) == [left] && curtains() == 1)
        print("a new screen gets its own curtain, and a removed screen takes its curtain away: ok")

        screens = [screen(left, other, scale: 2)]
        precondition(drawn { notify(NSWorkspace.activeSpaceDidChangeNotification) }.count == 1 && curtains() == 1)
        print("a Space with another wallpaper redraws the curtain: ok")

        screens = [screen(left, photo, scale: 2)]
        asked = 0
        precondition(drawn { spin(2.5) { !shown.isEmpty } }.count == 1 && asked > 0 && curtains() == 1)
        print("a new wallpaper picked in System Settings shows within two seconds, with no notice from macOS: ok")

        let teal = NSColor(srgbRed: 0.1, green: 0.5, blue: 0.6, alpha: 1), plum = NSColor(srgbRed: 0.4, green: 0.1, blue: 0.4, alpha: 1)
        screens = [screen(left, moving, [.fillColor: teal]), screen(right, broken, [.fillColor: plum])]
        autoreleasepool {
            let flat = drawn { notify(NSApplication.didChangeScreenParametersNotification) }
            precondition(flat.map(\.backgroundColor) == [teal, plum] && flat.allSatisfy { $0.contentView?.layer?.contents == nil })
        }
        print("a moving wallpaper and a picture that can't be read give the plain wallpaper color: ok")

        screens = [screen(left, big, scale: 2)]
        autoreleasepool {
            let large = drawn { notify(NSApplication.didChangeScreenParametersNotification) }
            precondition(image(large)?.width == 2880 && image(large)?.height == 1920 && large.first?.contentView?.layer?.contentsScale == 2, "\(String(describing: image(large)))")
        }
        print("a 6000×4000 picture on a 1440×900 Retina screen is decoded at 2880×1920, just enough to cover it: ok")

        let scalings: [([NSWorkspace.DesktopImageOptionKey: Any], CALayerContentsGravity)] = [
            ([.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue as NSNumber, .allowClipping: true as NSNumber], .resizeAspectFill),
            ([.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue as NSNumber, .allowClipping: false as NSNumber], .resizeAspect),
            ([.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue as NSNumber], .resize),
            ([.imageScaling: NSImageScaling.scaleNone.rawValue as NSNumber], .center),
        ]
        for (options, gravity) in scalings {
            screens = [screen(left, photo, options)]
            precondition(drawn { notify(NSWorkspace.didActivateApplicationNotification) }.map { $0.contentView?.layer?.contentsGravity } == [gravity])
        }
        print("Fill Screen, Fit to Screen, Stretch to Fill Screen and Center keep their look on the curtain, and picking another one redraws it: ok")

        screens = [screen(left, look, scale: 2)]
        autoreleasepool {
            let light = drawn { notify(NSWorkspace.activeSpaceDidChangeNotification) }
            precondition(image(light)?.width == 2 && light.first?.appearance?.name == .aqua)
            system("Dark")
            let dark = drawn { NSApp.appearance = darkAqua }
            precondition(image(dark)?.width == 1 && dark.first?.appearance?.name == .darkAqua)
            print("with pikapik set to Light or Dark the curtain shows the frame for the macOS look, and redraws as soon as pikapik's look changes: ok")
            system("Light")
            let back = drawn { spin(2.5) { !shown.isEmpty } }
            precondition(image(back)?.width == 2 && back.first?.appearance?.name == .aqua)
            print("macOS turning light while pikapik stays Dark brings the light frame within two seconds: ok")
        }

        let off = drawn {
            curtain.isOn = false
            changes.forEach(notify)
        }
        precondition(off.isEmpty && curtains() == 0)
        asked = 0
        spin(2.1) { false }
        precondition(asked == 0 && shown.isEmpty && curtains() == 0)
        precondition(RunLoop.current.limitDate(forMode: .default).map { $0.timeIntervalSinceNow > 1.5 } ?? true)
        print("turning it off leaves no curtain window, and nothing polls or redraws afterwards: ok")

        screens = [screen(left, photo, scale: 2), screen(right, photo)]
        let quitting = DesktopCurtain()
        precondition(drawn { quitting.isOn = true }.count == 2 && curtains() == 2)
        let quit = drawn {
            quitting.isOn = false
            notify(NSWorkspace.didActivateApplicationNotification)
        }
        precondition(quit.isEmpty && curtains() == 0)
        print("quitting with it on takes every curtain away, the same way pikapik turns it off on the way out: ok")

        precondition(DesktopCurtain.settingsLink.absoluteString == "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
        print("the Open button below the switch goes to Desktop & Dock in System Settings: ok")

        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).contains { $0[kCGWindowOwnerPID as String] as? Int32 == getpid() }
        precondition(!onScreen && !NSApp.windows.contains(where: \.isVisible))
        print("the test showed nothing on screen: ok")
    }
}
