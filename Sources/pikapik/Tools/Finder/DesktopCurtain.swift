import AppKit

#if APPSTORE
/// The sandbox can't change the Show items setting, so the App Store build hides the desktop icons with a curtain:
/// one window per screen just above the icons, showing the wallpaper. Clicks go through it to the desktop.
final class DesktopCurtain {
    struct Screen {
        let frame: CGRect
        let scale: CGFloat
        let url: URL?
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    static let settingsLink = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    static var screens: () -> [Screen] = {
        NSScreen.screens.map { Screen(frame: $0.frame, scale: $0.backingScaleFactor, url: NSWorkspace.shared.desktopImageURL(for: $0), options: NSWorkspace.shared.desktopImageOptions(for: $0) ?? [:]) }
    }
    static var show: (NSWindow) -> Void = { $0.orderBack(nil) } // below the pet, which lives at the same level

    var isOn = false {
        didSet {
            if isOn != oldValue { watch() }
            update()
        }
    }
    private var windows: [NSWindow] = []
    private var drawn: [String] = []
    private var timer: Timer?
    private var appearance: NSKeyValueObservation?

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        // Screens come and go, each Space has its own wallpaper, and a new wallpaper is picked in another app.
        for (center, name) in [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.didActivateApplicationNotification),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.update() }
        }
    }

    private func watch() {
        timer?.invalidate()
        timer = isOn ? Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.update() } : nil
        timer?.tolerance = 0.5
        appearance = isOn ? NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in self?.update() } : nil
    }

    private func update() {
        let screens = isOn ? Self.screens() : []
        let wallpapers = screens.map(Self.wallpaper)
        guard wallpapers != drawn else { return }
        let old = windows
        windows = screens.map(Self.curtain)
        old.forEach { $0.orderOut(nil) }
        drawn = wallpapers
    }

    private static var dark: Bool {
        WallpaperFrame.dark(own: NSApp.appearance, effective: NSApp.effectiveAppearance, system: UserDefaults.standard.string(forKey: "AppleInterfaceStyle"))
    }

    private static func wallpaper(_ screen: Screen) -> String {
        "\(screen.frame) \(screen.scale) \(dark) \(screen.url?.path ?? "") \(screen.options)"
    }

    private static func curtain(_ screen: Screen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.hasShadow = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = screen.options[.fillColor] as? NSColor ?? .windowBackgroundColor
        // Moving (Aerial) wallpapers all report the default picture, so they get the plain color.
        // The real frame would need Screen Recording.
        _ = FolderAccess.reopen()
        if let url = screen.url, url.lastPathComponent != "DefaultDesktop.heic",
           let picture = picture(url, covering: CGSize(width: screen.frame.width * screen.scale, height: screen.frame.height * screen.scale)) {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.contents = picture
            view.layer?.contentsScale = screen.scale
            view.layer?.contentsGravity = gravity(screen.options)
            window.contentView = view
        }
        show(window)
        return window
    }

    /// Decoded only as large as the screen needs: a 6K wallpaper at full size would hold 140 MB.
    private static func picture(_ url: URL, covering pixels: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frame = WallpaperFrame.index(source, dark: dark)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let scale = min(1, max(pixels.width / width, pixels.height / height))
        return CGImageSourceCreateThumbnailAtIndex(source, frame, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: (max(width, height) * scale).rounded(.up),
        ] as CFDictionary)
    }

    private static func gravity(_ options: [NSWorkspace.DesktopImageOptionKey: Any]) -> CALayerContentsGravity {
        switch (options[.imageScaling] as? UInt).flatMap(NSImageScaling.init) {
        case .scaleAxesIndependently: .resize
        case .scaleNone: .center
        default: options[.allowClipping] as? Bool == false ? .resizeAspect : .resizeAspectFill
        }
    }
}
#endif

enum WallpaperFrame {
    static func dark(own: NSAppearance?, effective: NSAppearance, system: String?) -> Bool {
        own == nil ? effective.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua : system == "Dark"
    }

    static func index(_ source: CGImageSource, dark: Bool) -> Int {
        let tags = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCopyTags($0) as? [CGImageMetadataTag] } ?? []
        for tag in tags where CGImageMetadataTagCopyNamespace(tag) as String? == "http://ns.apple.com/namespace/1.0/" {
            guard let name = CGImageMetadataTagCopyName(tag) as String?, ["apr", "solar", "h24"].contains(name),
                  let text = CGImageMetadataTagCopyValue(tag) as? String,
                  let data = Data(base64Encoded: text),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let pair = (name == "apr" ? plist : plist["ap"]) as? [String: Any],
                  let index = pair[dark ? "d" : "l"] as? Int,
                  (0..<CGImageSourceGetCount(source)).contains(index) else { continue }
            return index
        }
        return 0
    }
}
