import AppKit
import CoreGraphics

/// A display that exists only in software. macOS draws the desktop on it at twice the size it looks like, and a
/// monitor that mirrors it shows that sharp picture. The classes behind it are private to CoreGraphics: every class,
/// selector and type is checked before first use, so a macOS that changes them only takes the larger steps away.
/// The display lives while this object does and needs a running app; it ends with the process.
@MainActor final class VirtualDisplay {
    static var isAvailable: Bool { runtime != nil }

    let id: CGDirectDisplayID
    /// The name it goes by, in System Settings › Displays too.
    let name: String
    /// The size it looks like, in points; macOS draws it at twice this.
    let width: Int, height: Int
    private let display: VirtualDisplayObject

    private static let runtime = Runtime()

    init?(name: String, vendor: UInt32, product: UInt32, serial: UInt32, millimeters: CGSize,
          width: Int, height: Int, refresh: Double, primaries: [CGPoint]?) {
        guard let runtime = Self.runtime else { return nil }
        let descriptor = runtime.descriptor.init()
        descriptor.setName(name)
        descriptor.setVendorID(vendor)
        descriptor.setProductID(product)
        descriptor.setSerialNum(serial)
        descriptor.setSizeInMillimeters(millimeters)
        descriptor.setMaxPixelsWide(UInt32(2 * width))
        descriptor.setMaxPixelsHigh(UInt32(2 * height))
        if let primaries, primaries.count == 4 {
            descriptor.setRedPrimary(primaries[0])
            descriptor.setGreenPrimary(primaries[1])
            descriptor.setBluePrimary(primaries[2])
            descriptor.setWhitePoint(primaries[3])
        }
        descriptor.setQueue(.main)
        guard let display = runtime.display.init(descriptor: descriptor), display.displayID != 0 else { return nil }
        // One mode, in points: with the pixel limit at exactly twice it, macOS offers that size at 2x (`sharpMode`).
        let settings = runtime.settings.init()
        settings.setHiDPI(1)
        settings.setModes([runtime.mode.init(width: UInt32(width), height: UInt32(height), refreshRate: refresh)])
        guard display.applySettings(settings) else { return nil }
        id = display.displayID
        self.name = name
        self.width = width
        self.height = height
        self.display = display
    }

    /// The mode that draws it sharp: the size it looks like, at twice that in pixels. A display macOS has not seen
    /// before starts at its full pixel size at 1x instead.
    var sharpMode: CGDisplayMode? {
        DisplayScaler.modes(of: id).first { $0.width == width && $0.height == height && $0.pixelWidth == 2 * width && $0.isUsableForDesktopGUI() }
    }

    var isSharp: Bool {
        CGDisplayCopyDisplayMode(id).map { $0.width == width && $0.pixelWidth == 2 * width } ?? false
    }

    /// The monitor behind a display: one of pikapik's virtual displays maps to the monitor it was made for, any
    /// other display to itself. It goes by identity, with the unit number of one of two identical monitors, so it
    /// holds before the mirror is set up and from any thread.
    nonisolated static func physical(of id: CGDirectDisplayID) -> CGDirectDisplayID {
        let vendor = CGDisplayVendorNumber(id), product = CGDisplayModelNumber(id), serial = CGDisplaySerialNumber(id)
        let monitors = onlineDisplays().filter { other in
            other != id && CGDisplayVendorNumber(other) == vendor && CGDisplayModelNumber(other) == product
                && DisplayScaleMath.isVirtual(serial, vendor: vendor, product: product, serial: CGDisplaySerialNumber(other), unit: CGDisplayUnitNumber(other))
        }
        return monitors.first { CGDisplayMirrorsDisplay($0) == id } ?? monitors.first ?? id
    }

    nonisolated static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// The panel's red, green and blue primaries and white point as CIE xy, from the color profile macOS uses for
    /// it, so the virtual display describes the same panel. macOS still gives the virtual display a profile that
    /// converts like sRGB (measured), so wide-color content is clipped at virtual steps. Nil when the profile has no
    /// matrix.
    nonisolated static func primaries(of display: CGDirectDisplayID) -> [CGPoint]? {
        guard let data = CGDisplayCopyColorSpace(display).copyICCData() as Data? else { return nil }
        let bytes = [UInt8](data)
        func word(_ at: Int) -> UInt32? {
            at >= 0 && at + 4 <= bytes.count ? bytes[at ..< at + 4].reduce(0) { $0 << 8 | UInt32($1) } : nil
        }
        func numbers(_ tag: String, _ count: Int) -> [Double]? {
            let signature = tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            for index in 0 ..< Int(min(word(128) ?? 0, 100)) {
                guard word(132 + 12 * index) == signature, let offset = word(136 + 12 * index) else { continue }
                let values = (0 ..< count).compactMap { word(Int(offset) + 8 + 4 * $0).map { Double(Int32(bitPattern: $0)) / 65536 } }
                return values.count == count ? values : nil
            }
            return nil
        }
        // The colors are stored adapted to the profile white D50; `chad` is that adaptation, its inverse undoes it.
        guard let red = numbers("rXYZ", 3), let green = numbers("gXYZ", 3), let blue = numbers("bXYZ", 3),
              let adaptation = numbers("chad", 9).flatMap(inverse) else { return nil }
        let white = (0 ..< 3).map { red[$0] + green[$0] + blue[$0] }
        let points = [red, green, blue, white].map { color -> CGPoint in
            let xyz = (0 ..< 3).map { row in (0 ..< 3).reduce(0.0) { $0 + adaptation[3 * row + $1] * color[$1] } }
            let sum = xyz.reduce(0, +)
            return CGPoint(x: xyz[0] / sum, y: xyz[1] / sum)
        }
        return points.allSatisfy { $0.x > 0 && $0.x < 1 && $0.y > 0 && $0.y < 1 } ? points : nil
    }

    private nonisolated static func inverse(_ m: [Double]) -> [Double]? {
        let det = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
        guard abs(det) > 1e-9 else { return nil }
        return [m[4] * m[8] - m[5] * m[7], m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
                m[5] * m[6] - m[3] * m[8], m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
                m[3] * m[7] - m[4] * m[6], m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3]].map { $0 / det }
    }
}

/// One monitor and what pikapik shows on it: its own mode for a step it offers itself, otherwise a mirror of a
/// virtual display. Everything is undone by `release()`, and by macOS when the process ends.
@MainActor final class DisplayScaler {
    struct Refusal: Error, CustomStringConvertible {
        /// unavailable: no sharp picture at that size; refused: macOS said no and the picture stayed; lost: it went back.
        enum Reason { case unavailable, refused, lost }
        let reason: Reason
        let description: String
    }

    let display: CGDirectDisplayID
    let name: String
    let vendor: UInt32, product: UInt32, serial: UInt32
    /// The unit number of one of two identical monitors, which its virtual displays carry; nil for any other monitor.
    let unit: UInt32?
    let nativeWidth: Int, nativeHeight: Int
    let millimeters: CGSize
    let refresh: Double
    let primaries: [CGPoint]?
    let modes: [CGDisplayMode]
    private(set) var virtual: VirtualDisplay? {
        didSet {
            if let old = oldValue?.id, old != virtual?.id { PointerNudge.track(old, false) }
            if let id = virtual?.id { PointerNudge.track(id, true) }
        }
    }
    /// The step pikapik put on screen, nil while the monitor shows its own picture.
    private(set) var percent: Int?
    /// The monitor's own mode before pikapik changed it, and the one pikapik set.
    private(set) var original: CGDisplayMode?
    private var applied: CGDisplayMode?
    private var generation = 0

    /// Changes are made for this app only, so macOS undoes them when the process ends.
    static let option = CGConfigureOption.forAppOnly

    /// Reads the monitor while it shows its own picture: mirroring hides its name, size and colors.
    init?(display: CGDirectDisplayID, name: String, unit: UInt32?) {
        let modes = Self.modes(of: display)
        guard let native = Self.native(in: modes) else { return nil }
        self.display = display
        self.name = name
        vendor = CGDisplayVendorNumber(display)
        product = CGDisplayModelNumber(display)
        serial = CGDisplaySerialNumber(display)
        self.unit = unit
        nativeWidth = native.pixelWidth
        nativeHeight = native.pixelHeight
        millimeters = CGDisplayScreenSize(display)
        let rate = CGDisplayCopyDisplayMode(display)?.refreshRate ?? 0
        refresh = rate > 0 ? rate : 60
        primaries = VirtualDisplay.primaries(of: display)
        self.modes = modes
    }

    /// True once pikapik has changed anything on this monitor.
    var changed: Bool { virtual != nil || applied != nil }

    /// Whether what pikapik set is still on screen, sharp: the monitor in the virtual display's 2x mode, or the mode.
    var holds: Bool {
        guard CGDisplayIsOnline(display) != 0 else { return false }
        if let virtual {
            guard CGDisplayMirrorsDisplay(display) == virtual.id, let shown = CGDisplayCopyDisplayMode(virtual.id),
                  let mode = CGDisplayCopyDisplayMode(display) else { return false }
            return DisplayScaleMath.mirrorHolds(width: virtual.width, shown: Self.math(shown), monitor: Self.math(mode))
        }
        if let applied { return Self.same(CGDisplayCopyDisplayMode(display), applied) }
        return true
    }

    /// macOS put the monitor's own mode back over the 2x mode pikapik set: it does so for every monitor whenever a
    /// virtual display comes or goes.
    var putBack: Bool {
        guard virtual == nil, let applied, let original else { return false }
        let mode = CGDisplayCopyDisplayMode(display)
        return !Self.same(mode, applied) && Self.same(mode, original)
    }

    /// The monitor's own mode for a step, nil when only a virtual display can show it.
    func nativeMode(_ percent: Int) -> CGDisplayMode? {
        let listed = modes.map(Self.math)
        guard let match = DisplayScaleMath.nativeMatch(percent: percent, nativeWidth: nativeWidth, nativeHeight: nativeHeight,
                                                       modes: listed, refresh: refresh) else { return nil }
        return listed.firstIndex(of: match).map { modes[$0] }
    }

    /// Puts a step on the monitor. A refusal leaves the picture it had or the monitor's own (`Refusal.reason` says
    /// which); a newer call or `release()` makes it throw `CancellationError` without touching anything.
    func show(_ percent: Int) async throws {
        generation += 1
        let mine = generation
        if !changed { original = CGDisplayCopyDisplayMode(display) }
        if let mode = nativeMode(percent) {
            // The monitor's own mode comes back by itself once pikapik's changes end.
            if let original, Self.same(original, mode) { return try await restore() }
            // The mirror and the virtual display end before the mode is set: macOS puts the monitor's own mode back
            // when a display leaves, so a mode set earlier would not stay.
            let gone = virtual?.id
            if let gone {
                if CGDisplayMirrorsDisplay(display) == gone,
                   !Self.configure({ CGConfigureDisplayMirrorOfDisplay($0, display, kCGNullDirectDisplay) }) {
                    throw Refusal(reason: .refused, description: "ending the mirror was refused")
                }
                virtual = nil
                self.percent = nil
                guard try await wait(5, mine, until: { Self.offline(gone) }) else {
                    throw Refusal(reason: .lost, description: "the virtual display did not go away")
                }
            }
            if !Self.same(CGDisplayCopyDisplayMode(display), mode) {
                guard Self.configure({ CGConfigureDisplayWithDisplayMode($0, display, mode, nil) }) else {
                    // undo() takes back a mode pikapik set before, so only a monitor pikapik had not changed stays as it was.
                    let reason: Refusal.Reason = gone == nil && applied == nil ? .refused : .lost
                    undo()
                    throw Refusal(reason: reason, description: "the mode \(mode.width)x\(mode.height) was refused")
                }
            }
            applied = mode
            self.percent = percent
            guard try await wait(3, mine, until: { Self.same(CGDisplayCopyDisplayMode(display), mode) }) else {
                undo()
                throw Refusal(reason: .lost, description: "the mode \(mode.width)x\(mode.height) did not stay")
            }
            return
        }
        guard percent > 100 else { return try await restore() }
        let size = DisplayScaleMath.looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
        let hadVirtual = virtual != nil
        if let current = virtual, current.width == size.width {
            if holds { return }
            // A mirror macOS ended goes back onto the same display: a new one would change the set of displays, and
            // macOS then puts that set's stored arrangement back, which ends another monitor's mirror in turn.
            if !Self.offline(current.id), try await sharpen(current, mine), mirror(onto: current) {
                try await wait(2, mine)
                if holds { return }
            }
            let mode = CGDisplayCopyDisplayMode(display).map { "\($0.width)x\($0.height) (\($0.pixelWidth) px wide)" } ?? "none"
            let state = "online \(!Self.offline(current.id)), mirrored \(CGDisplayMirrorsDisplay(display) == current.id), monitor at \(mode)"
            Log.note("DisplayScale: \(name) did not take its mirror back (\(state)), making a new display")
        }
        // The old display goes before the new one comes: macOS puts a stored arrangement back when a display leaves,
        // and that breaks a mirror already on the new display. One identity is never online twice either.
        if let old = virtual?.id {
            undo()
            guard try await wait(5, mine, until: { Self.offline(old) }) else {
                throw Refusal(reason: .lost, description: "the virtual display did not go away")
            }
            original = CGDisplayCopyDisplayMode(display)
        }
        guard let next = VirtualDisplay(
            name: String(localized: "\(name.isEmpty ? String(localized: "Monitor") : name) — enlarged by pikapik"), vendor: vendor, product: product,
            serial: DisplayScaleMath.serial(vendor: vendor, product: product, serial: serial, unit: unit, percent: percent),
            millimeters: millimeters, width: size.width, height: size.height, refresh: refresh, primaries: primaries)
        else { throw Refusal(reason: .unavailable, description: "no virtual display for \(size.width)x\(size.height)") }
        guard try await sharpen(next, mine)
        else { throw Refusal(reason: .unavailable, description: "the virtual display did not reach \(size.width)x\(size.height) at 2x") }
        // From the monitor's own 2x mode or another step, the mirror starts at its own picture: a refusal then leaves
        // that, not the step.
        let leftNative = hadVirtual || applied != nil
        if let mode = applied {
            // The mirror starts from the monitor's own mode, so ending the mirror always brings that mode back.
            if let original, Self.same(CGDisplayCopyDisplayMode(display), mode) {
                guard Self.configure({ CGConfigureDisplayWithDisplayMode($0, display, original, nil) }),
                      try await wait(3, mine, until: { Self.same(CGDisplayCopyDisplayMode(display), original) }) else {
                    undo()
                    throw Refusal(reason: .lost, description: "the mode \(original.width)x\(original.height) did not come back")
                }
            }
            applied = nil
            self.percent = nil
        }
        guard mirror(onto: next)
        else { throw Refusal(reason: leftNative ? .lost : .refused, description: "mirroring onto \(size.width)x\(size.height) was refused") }
        virtual = next
        self.percent = percent
        try await wait(2, mine)
        guard holds else {
            undo()
            throw Refusal(reason: .lost, description: "the mirror at \(size.width)x\(size.height) did not hold at 2x")
        }
    }

    /// Back to the monitor's own picture, waiting until the virtual display is gone; a newer call or `release()` makes
    /// it throw `CancellationError`.
    func restore() async throws {
        generation += 1
        let mine = generation
        let gone = virtual?.id
        undo()
        if let gone { try await wait(5, mine) { Self.offline(gone) } }
    }

    /// Sets a virtual display's sharp mode while nothing shows it yet, so the monitor changes only once, with the mirror.
    private func sharpen(_ next: VirtualDisplay, _ mine: Int) async throws -> Bool {
        guard try await wait(3, mine, until: { next.isSharp || next.sharpMode != nil }),
              next.isSharp || next.sharpMode.map({ mode in Self.configure { CGConfigureDisplayWithDisplayMode($0, next.id, mode, nil) } }) == true
        else { return false }
        return try await wait(3, mine, until: { next.isSharp })
    }

    /// One transaction: the monitor mirrors the virtual display, which takes the monitor's place.
    private func mirror(onto next: VirtualDisplay) -> Bool {
        let origin = place(width: next.width, height: next.height)
        return Self.configure { config in
            let mirrored = CGConfigureDisplayMirrorOfDisplay(config, display, next.id)
            return mirrored == .success ? CGConfigureDisplayOrigin(config, next.id, Int32(origin.x), Int32(origin.y)) : mirrored
        }
    }

    /// Where a smaller or larger picture keeps the monitor's place in the arrangement (`DisplayScaleMath.origin`).
    private func place(width: Int, height: Int) -> CGPoint {
        let others = VirtualDisplay.onlineDisplays().filter { VirtualDisplay.physical(of: $0) != display }.map(CGDisplayBounds)
        return DisplayScaleMath.origin(of: CGDisplayBounds(display), among: others, width: width, height: height)
    }

    /// Whether a display left the online list; `CGDisplayIsOnline` keeps answering yes for a removed virtual display.
    private static func offline(_ id: CGDirectDisplayID) -> Bool {
        !VirtualDisplay.onlineDisplays().contains(id)
    }

    /// Back to the monitor's own picture at once, for quitting: the virtual display goes away in about 0.1 s.
    func release() {
        generation += 1
        undo()
    }

    private func undo() {
        // Only pikapik's own mirror is ended: a broken one needs nothing, and one made by someone else is theirs.
        if let virtual, CGDisplayMirrorsDisplay(display) == virtual.id {
            _ = Self.configure { CGConfigureDisplayMirrorOfDisplay($0, display, kCGNullDirectDisplay) }
        }
        if let applied, let original, Self.same(CGDisplayCopyDisplayMode(display), applied) {
            _ = Self.configure { CGConfigureDisplayWithDisplayMode($0, display, original, nil) }
        }
        applied = nil
        original = nil
        virtual = nil
        percent = nil
    }

    /// Waits until `done` or the time is up; throws when a newer call took over meanwhile.
    @discardableResult
    private func wait(_ seconds: Double, _ mine: Int, until done: () -> Bool = { false }) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() {
            guard Date() < deadline else { return false }
            try await Task.sleep(nanoseconds: 50_000_000)
            guard mine == generation else { throw CancellationError() }
        }
        return true
    }

    static func modes(of display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// The panel's own pixels: the mode macOS marks native, else the largest 1x mode.
    static func native(in modes: [CGDisplayMode]) -> CGDisplayMode? {
        modes.filter { $0.ioFlags & 0x0200_0000 != 0 && $0.pixelWidth == $0.width }.max { $0.pixelWidth < $1.pixelWidth }
            ?? modes.filter { $0.pixelWidth == $0.width && $0.isUsableForDesktopGUI() }.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
    }

    private static func math(_ mode: CGDisplayMode) -> DisplayScaleMath.Mode {
        DisplayScaleMath.Mode(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                              refresh: mode.refreshRate, usable: mode.isUsableForDesktopGUI())
    }

    private static func same(_ a: CGDisplayMode?, _ b: CGDisplayMode) -> Bool {
        guard let a else { return false }
        return a.width == b.width && a.height == b.height && a.pixelWidth == b.pixelWidth && a.pixelHeight == b.pixelHeight
            && abs(a.refreshRate - b.refreshRate) < 0.5
    }

    private static func configure(_ change: (CGDisplayConfigRef) -> CGError) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard change(config) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, option) == .success
    }
}

// MARK: - The private classes, reached through the Objective-C runtime

@objc private protocol VirtualDisplayDescriptorObject {
    init()
    @objc(setName:) func setName(_ name: String)
    @objc(setVendorID:) func setVendorID(_ value: UInt32)
    @objc(setProductID:) func setProductID(_ value: UInt32)
    @objc(setSerialNum:) func setSerialNum(_ value: UInt32)
    @objc(setSizeInMillimeters:) func setSizeInMillimeters(_ size: CGSize)
    @objc(setMaxPixelsWide:) func setMaxPixelsWide(_ value: UInt32)
    @objc(setMaxPixelsHigh:) func setMaxPixelsHigh(_ value: UInt32)
    @objc(setRedPrimary:) func setRedPrimary(_ point: CGPoint)
    @objc(setGreenPrimary:) func setGreenPrimary(_ point: CGPoint)
    @objc(setBluePrimary:) func setBluePrimary(_ point: CGPoint)
    @objc(setWhitePoint:) func setWhitePoint(_ point: CGPoint)
    @objc(setQueue:) func setQueue(_ queue: DispatchQueue)
}

@objc private protocol VirtualDisplayModeObject {
    @objc(initWithWidth:height:refreshRate:) init(width: UInt32, height: UInt32, refreshRate: Double)
}

@objc private protocol VirtualDisplaySettingsObject {
    init()
    @objc(setHiDPI:) func setHiDPI(_ value: UInt32)
    @objc(setModes:) func setModes(_ modes: [AnyObject])
}

@objc private protocol VirtualDisplayObject {
    @objc(initWithDescriptor:) init?(descriptor: VirtualDisplayDescriptorObject)
    @objc(applySettings:) func applySettings(_ settings: VirtualDisplaySettingsObject) -> Bool
    var displayID: UInt32 { get }
}

private struct Runtime {
    let descriptor: VirtualDisplayDescriptorObject.Type
    let mode: VirtualDisplayModeObject.Type
    let settings: VirtualDisplaySettingsObject.Type
    let display: VirtualDisplayObject.Type

    /// Nil unless every class and method is there with the types declared above (offsets aside).
    init?() {
        let point = "v@:{CGPoint=dd}", number = "v@:I"
        guard let descriptor = Self.load("CGVirtualDisplayDescriptor", [
                  "setName:": "v@:@", "setVendorID:": number, "setProductID:": number, "setSerialNum:": number,
                  "setSizeInMillimeters:": "v@:{CGSize=dd}", "setMaxPixelsWide:": number, "setMaxPixelsHigh:": number,
                  "setRedPrimary:": point, "setGreenPrimary:": point, "setBluePrimary:": point, "setWhitePoint:": point,
                  "setQueue:": "v@:@"]),
              let mode = Self.load("CGVirtualDisplayMode", ["initWithWidth:height:refreshRate:": "@@:IId"]),
              let settings = Self.load("CGVirtualDisplaySettings", ["setHiDPI:": number, "setModes:": "v@:@"]),
              let display = Self.load("CGVirtualDisplay", ["initWithDescriptor:": "@@:@", "applySettings:": "B@:@", "displayID": "I@:"])
        else { return nil }
        self.descriptor = unsafeBitCast(descriptor, to: VirtualDisplayDescriptorObject.Type.self)
        self.mode = unsafeBitCast(mode, to: VirtualDisplayModeObject.Type.self)
        self.settings = unsafeBitCast(settings, to: VirtualDisplaySettingsObject.Type.self)
        self.display = unsafeBitCast(display, to: VirtualDisplayObject.Type.self)
    }

    private static func load(_ name: String, _ methods: [String: String]) -> AnyClass? {
        guard let type = NSClassFromString(name), type is NSObject.Type else { return nil }
        for (selector, expected) in methods {
            guard let method = class_getInstanceMethod(type, NSSelectorFromString(selector)),
                  let encoding = method_getTypeEncoding(method) else { return nil }
            var types = String(cString: encoding).filter { !$0.isNumber }
            if types.hasPrefix("c") { types = "B" + types.dropFirst() }  // BOOL is a signed char on Intel
            guard types == expected else { return nil }
        }
        return type
    }
}
