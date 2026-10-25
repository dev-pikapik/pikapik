import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct TestDesktopCurtain {
    static func wallpaper(_ tag: String? = nil, _ value: String = "") -> CGImageSource {
        let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 2, nil)!
        let metadata = CGImageMetadataCreateMutable()
        if let tag {
            precondition(CGImageMetadataRegisterNamespaceForPrefix(metadata, "http://ns.apple.com/namespace/1.0/" as CFString, "apple_desktop" as CFString, nil))
            precondition(CGImageMetadataSetValueWithPath(metadata, nil, "apple_desktop:\(tag)" as CFString, value as CFString))
        }
        CGImageDestinationAddImageAndMetadata(destination, pixel, metadata, nil)
        CGImageDestinationAddImage(destination, pixel, nil)
        precondition(CGImageDestinationFinalize(destination))
        let source = CGImageSourceCreateWithData(data, nil)!
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
    }
}
