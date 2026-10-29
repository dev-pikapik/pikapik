import CoreGraphics
import Foundation

/// Sizes for a monitor shown larger and still sharp: every step draws at twice its "looks like" size in points.
enum DisplayScaleMath {
    static let steps = [100, 125, 150, 175, 200]
    /// The widest picture Apple silicon draws for one display; 8192 is the absolute limit.
    static let maxBackingWidth = 6720
    static let minLooksLikeHeight = 600
    static let tolerance = 0.03

    struct Mode: Equatable {
        var width, height, pixelWidth, pixelHeight: Int
        var refresh: Double
        var usable: Bool
    }

    /// The size in points the desktop gets at `percent`: an even width, so the picture splits evenly at 2x.
    static func looksLike(nativeWidth: Int, nativeHeight: Int, percent: Int) -> (width: Int, height: Int) {
        let width = Int((Double(nativeWidth) * 50 / Double(percent)).rounded()) * 2
        let height = Int((Double(nativeHeight) * 100 / Double(percent)).rounded())
        return (width, height)
    }

    /// `maxBackingWidth`: the widest picture the monitor's display pipe takes. Steps wider than that give way to the
    /// nearest size that still fits, so a monitor on a narrow pipe gets, say, 135 % in place of 125 %.
    static func steps(nativeWidth: Int, nativeHeight: Int, maxBackingWidth: Int = maxBackingWidth) -> [Int] {
        let fits = { (percent: Int) in
            let size = looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
            return 2 * size.width <= maxBackingWidth && size.height >= minLooksLikeHeight
        }
        let kept = steps.filter { $0 == 100 || fits($0) }
        let nearest = Int((200 * Double(nativeWidth) / Double(maxBackingWidth)).rounded(.up))
        let dropped = steps.contains { $0 > 100 && $0 < nearest }
        return dropped && nearest < 200 && !kept.contains(nearest) && fits(nearest) ? (kept + [nearest]).sorted() : kept
    }

    static func percent(nativeWidth: Int, looksLikeWidth: Int) -> Int {
        guard looksLikeWidth > 0 else { return 100 }
        return Int((100 * Double(nativeWidth) / Double(looksLikeWidth)).rounded())
    }

    /// The monitor's own mode for a step, nil when only a virtual display can show it. A 2x mode wider than the
    /// monitor's `pipe` doesn't count: macOS lists it, but it shows purple stripes and lags there.
    static func nativeMatch(percent: Int, nativeWidth: Int, nativeHeight: Int, modes: [Mode], refresh: Double, pipe: Int = .max) -> Mode? {
        if percent == 100 {
            return modes.filter { $0.usable && $0.width == nativeWidth && $0.height == nativeHeight && $0.pixelWidth == nativeWidth && $0.pixelHeight == nativeHeight }
                .min { abs($0.refresh - refresh) < abs($1.refresh - refresh) }
        }
        let size = looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
        let off = { (mode: Mode) in
            max(abs(Double(mode.width - size.width)) / Double(size.width), abs(Double(mode.height - size.height)) / Double(size.height))
        }
        return modes.filter { $0.usable && $0.pixelWidth == 2 * $0.width && $0.pixelHeight == 2 * $0.height && off($0) <= tolerance && abs($0.refresh - refresh) <= 0.5
            && $0.pixelWidth <= pipe }
            .min { off($0) < off($1) }
    }

    /// The sizes above 100 % to add to a monitor model's own modes, as w,h pairs in points: every step any of this Mac's
    /// `pipes` takes, so the file suits whichever port the monitor is on, less those the monitor lists already.
    static func overrideSizes(nativeWidth: Int, nativeHeight: Int, pipes: [Int], listed: [Mode]) -> [Int] {
        let anyRate = listed.map { mode in var mode = mode; mode.refresh = 0; return mode }
        return Set(pipes.flatMap { steps(nativeWidth: nativeWidth, nativeHeight: nativeHeight, maxBackingWidth: $0) }).sorted()
            .filter { $0 > 100 && nativeMatch(percent: $0, nativeWidth: nativeWidth, nativeHeight: nativeHeight, modes: anyRate, refresh: 0) == nil }
            .flatMap { percent in
                let size = looksLike(nativeWidth: nativeWidth, nativeHeight: nativeHeight, percent: percent)
                return [size.width, size.height]
            }
    }

    /// The serial number of the virtual display for one monitor and step: FNV-1a over the monitor's identity and the
    /// step, so macOS remembers each step as its own display and never mistakes it for the monitor itself. One of two
    /// identical monitors adds its unit number, so each gets its own; any other monitor keeps the number it always had.
    static func serial(vendor: UInt32, product: UInt32, serial: UInt32, unit: UInt32? = nil, percent: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for value in [vendor, product, serial, UInt32(truncatingIfNeeded: percent)] + [unit].compactMap({ $0 }) {
            for shift in stride(from: 0, to: 32, by: 8) {
                hash = (hash ^ (value >> UInt32(shift) & 0xFF)) &* 16_777_619
            }
        }
        while hash == 0 || hash == serial { hash &+= 1 }
        return hash
    }

    /// Whether a display with this serial number is one of the monitor's virtual displays, at any size above 100 % (a
    /// narrow pipe gives, say, 135 % in place of a step), made with its unit number or without: a monitor that just got
    /// an identical twin still has the one made without.
    static func isVirtual(_ display: UInt32, vendor: UInt32, product: UInt32, serial: UInt32, unit: UInt32) -> Bool {
        [nil, unit].contains { twin in (101...200).contains { Self.serial(vendor: vendor, product: product, serial: serial, unit: twin, percent: $0) == display } }
    }

    /// The saved size for one of two identical monitors whose id has none: macOS may hand out their unit numbers anew
    /// after a reconnection or a restart, so it takes a size saved for the same model (`key`, alone or with a unit
    /// number) under an id no monitor has now, the larger one if they differ.
    static func twinSize(saved: [String: Int], key: String, online: Set<String>) -> Int? {
        saved.filter { !online.contains($0.key) && ($0.key == key || $0.key.hasPrefix(key + "-")) }.values.max()
    }

    /// Whether a monitor mirroring a virtual display shows it sharp: the virtual display at its width and 2x, and the
    /// monitor in that very mode. The first time macOS meets a set of displays, another monitor's mirror can leave this
    /// monitor reported in its first listed mode, 800 x 600 at 2x: that is 2x too, so only the size tells it apart.
    static func mirrorHolds(width: Int, shown: Mode, monitor: Mode) -> Bool {
        shown.width == width && shown.pixelWidth == 2 * shown.width && monitor.width == shown.width
            && monitor.height == shown.height && monitor.pixelWidth == shown.pixelWidth && monitor.pixelHeight == shown.pixelHeight
    }

    enum Mend { case keep, repair, giveUp }

    /// A larger picture that broke goes back once; broken again within a minute of that, something else holds the
    /// monitor (a full-screen game, the other monitor's repair), so it keeps its own picture instead of a ping-pong.
    static func mend(holds: Bool, lastRepair: Date?, now: Date) -> Mend {
        if holds { return .keep }
        if let lastRepair, now.timeIntervalSince(lastRepair) < 60 { return .giveUp }
        return .repair
    }

    /// Where a picture of width × height points keeps a monitor's place (`here`): on each axis it keeps the edge that
    /// touches another display, the main one first, so a monitor left of the main one still touches it. The main
    /// display stays at 0,0, so the menu bar and the Dock stay where they were.
    static func origin(of here: CGRect, among others: [CGRect], width: Int, height: Int) -> CGPoint {
        guard here.origin != .zero else { return here.origin }
        let others = others.sorted { $0.origin == .zero && $1.origin != .zero }
        let beside = others.first { ($0.minX == here.maxX || $0.maxX == here.minX) && $0.minY < here.maxY && $0.maxY > here.minY }
        let stacked = others.first { ($0.minY == here.maxY || $0.maxY == here.minY) && $0.minX < here.maxX && $0.maxX > here.minX }
        return CGPoint(x: beside?.minX == here.maxX ? here.maxX - CGFloat(width) : here.minX,
                       y: stacked?.minY == here.maxY ? here.maxY - CGFloat(height) : here.minY)
    }

    /// Where the picture (`origin`) and every other display go when a monitor's picture becomes width × height points:
    /// a display touching the edge that moves moves with it, and so does one touching that display further out, so all
    /// keep touching in the order they had; one that touches none of them stays, and the main display never moves.
    /// macOS moves displays about while a mirror ends and a display comes or goes, so pikapik puts every one back.
    static func arrange(_ here: CGRect, among others: [CGRect], width: Int, height: Int) -> (here: CGPoint, others: [CGPoint]) {
        let new = origin(of: here, among: others, width: width, height: height)
        let dx = CGFloat(width) - here.width, dy = CGFloat(height) - here.height
        let left = new.x != here.minX, top = new.y != here.minY
        // The displays pushed along: those touching the moving edge of `here`, then those touching them, outward.
        let pushed = { (touches: (CGRect, CGRect) -> Bool) -> Set<Int> in
            var moved = Set<Int>(), next = [here]
            while let edge = next.popLast() {
                for (index, other) in others.enumerated() where other.origin != .zero && !moved.contains(index) && touches(edge, other) {
                    moved.insert(index)
                    next.append(other)
                }
            }
            return moved
        }
        let beside = pushed { (left ? $1.maxX == $0.minX : $1.minX == $0.maxX) && $1.minY < $0.maxY && $1.maxY > $0.minY }
        let stacked = pushed { (top ? $1.maxY == $0.minY : $1.minY == $0.maxY) && $1.minX < $0.maxX && $1.maxX > $0.minX }
        return (new, others.enumerated().map { index, other in
            CGPoint(x: other.minX + (beside.contains(index) ? (left ? -dx : dx) : 0), y: other.minY + (stacked.contains(index) ? (top ? -dy : dy) : 0))
        })
    }
}
