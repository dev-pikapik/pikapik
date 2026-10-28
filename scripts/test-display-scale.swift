import Foundation

@main
enum TestDisplayScale {
    static func mode(_ width: Int, _ height: Int, scale: Int = 2, refresh: Double = 60, usable: Bool = true) -> DisplayScaleMath.Mode {
        DisplayScaleMath.Mode(width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refresh: refresh, usable: usable)
    }

    static func main() {
        let steps = DisplayScaleMath.steps(nativeWidth: 3440, nativeHeight: 1440)
        precondition(steps == [100, 125, 150, 175, 200], "a 34-inch 3440x1440 monitor gets every step: \(steps)")
        let sizes = steps.map { DisplayScaleMath.looksLike(nativeWidth: 3440, nativeHeight: 1440, percent: $0) }
        precondition(sizes.map { $0.width } == [3440, 2752, 2294, 1966, 1720] && sizes.map { $0.height } == [1440, 1152, 960, 823, 720], "\(sizes)")
        precondition(DisplayScaleMath.percent(nativeWidth: 3440, looksLikeWidth: 0) == 100)
        print("3440x1440 steps and sizes: ok")

        precondition(DisplayScaleMath.steps(nativeWidth: 5120, nativeHeight: 2160) == [100, 175, 200], "125% and 150% of 5120x2160 would draw wider than 6720 pixels")
        precondition(DisplayScaleMath.steps(nativeWidth: 1920, nativeHeight: 1080) == [100, 125, 150, 175], "200% of 1920x1080 would look like 960x540, under 600 points high")
        precondition(DisplayScaleMath.steps(nativeWidth: 6016, nativeHeight: 3384) == [100, 200])
        for (width, height) in [(3440, 1440), (5120, 2160), (3840, 2160), (2560, 1440), (2560, 1080), (1920, 1080), (6016, 3384), (7680, 4320)] {
            for percent in DisplayScaleMath.steps(nativeWidth: width, nativeHeight: height) {
                let size = DisplayScaleMath.looksLike(nativeWidth: width, nativeHeight: height, percent: percent)
                precondition(size.width % 2 == 0, "\(width)x\(height) at \(percent)% splits evenly at 2x: \(size)")
                precondition(percent == 100 || 2 * size.width <= DisplayScaleMath.maxBackingWidth && size.height >= DisplayScaleMath.minLooksLikeHeight, "\(width)x\(height) at \(percent)%: \(size)")
                precondition(DisplayScaleMath.percent(nativeWidth: width, looksLikeWidth: size.width) == percent, "\(width)x\(height) reads back as \(percent)%: \(size)")
            }
        }
        print("steps a monitor gets, never wider than 6720 pixels: ok")

        let uhd = [mode(3840, 2160, scale: 1, refresh: 30), mode(3840, 2160, scale: 1), mode(3008, 1692), mode(2560, 1440, usable: false), mode(2560, 1440),
                   mode(2304, 1296), mode(2048, 1152), mode(1920, 1080, scale: 1), mode(1920, 1080), mode(1600, 900)]
        let match = { (percent: Int) in DisplayScaleMath.nativeMatch(percent: percent, nativeWidth: 3840, nativeHeight: 2160, modes: uhd, refresh: 60) }
        precondition(match(100) == mode(3840, 2160, scale: 1), "100% is the monitor's own size at its own refresh rate")
        precondition(match(125) == mode(3008, 1692), "3008x1692 is 2% off the 3072x1728 that 125% looks like")
        precondition(match(150) == mode(2560, 1440), "only usable modes count")
        precondition(match(175) == nil, "2304x1296 is 5% off 2194x1234, so only a virtual display shows 175%")
        precondition(match(200) == mode(1920, 1080), "a 1x mode is never sharp enough")
        precondition(DisplayScaleMath.nativeMatch(percent: 150, nativeWidth: 3840, nativeHeight: 2160, modes: [mode(2560, 1440, refresh: 30)], refresh: 60) == nil, "a step keeps the refresh rate")
        precondition(DisplayScaleMath.nativeMatch(percent: 150, nativeWidth: 3840, nativeHeight: 2160, modes: [mode(2560, 1440, refresh: 59.94)], refresh: 60) != nil)
        print("the monitor's own modes within 3%: ok")

        let samsung = { (percent: Int) in DisplayScaleMath.serial(vendor: 19501, product: 29455, serial: 810432311, percent: percent) }
        precondition(samsung(150) == 4_181_960_172, "macOS remembers each step by this number; a new number starts the step blurry at 1x again: \(samsung(150))")
        let serials = DisplayScaleMath.steps.map(samsung)
        precondition(Set(serials).count == serials.count && !serials.contains(0) && !serials.contains(810432311), "\(serials)")
        precondition(DisplayScaleMath.serial(vendor: 19501, product: 29455, serial: 1, percent: 150) != DisplayScaleMath.serial(vendor: 19501, product: 29455, serial: 2, percent: 150), "two monitors of one model get their own numbers")
        precondition(DisplayScaleMath.serial(vendor: 19501, product: 29455, serial: 0, percent: 150) != 0, "a monitor without a serial number gets one")
        print("serial numbers of the virtual displays: ok")

        let sharp = mode(2294, 960, refresh: 100)
        precondition(DisplayScaleMath.mirrorHolds(width: 2294, shown: sharp, monitor: sharp), "the Samsung at 150%: 2294x960 px 4588x1920")
        precondition(!DisplayScaleMath.mirrorHolds(width: 2294, shown: sharp, monitor: mode(800, 600, refresh: 100)),
                     "800x600 px 1600x1200, the monitor's first mode, is 2x too but not the mirror (the UXGA reading)")
        precondition(!DisplayScaleMath.mirrorHolds(width: 2294, shown: sharp, monitor: mode(3440, 1440, scale: 1, refresh: 100)),
                     "a monitor at its own mode draws the picture smaller, not sharp")
        precondition(!DisplayScaleMath.mirrorHolds(width: 2294, shown: mode(2294, 960, scale: 1), monitor: mode(2294, 960, scale: 1)), "1x is blurry")
        precondition(!DisplayScaleMath.mirrorHolds(width: 2294, shown: mode(800, 600), monitor: mode(800, 600)), "the virtual display at its first mode")
        let now = Date()
        precondition(DisplayScaleMath.mend(holds: true, lastRepair: now, now: now) == .keep)
        precondition(DisplayScaleMath.mend(holds: false, lastRepair: nil, now: now) == .repair, "the first break is put back")
        precondition(DisplayScaleMath.mend(holds: false, lastRepair: now.addingTimeInterval(-59), now: now) == .giveUp,
                     "broken again within a minute of the repair: the monitor keeps its own picture, no ping-pong")
        precondition(DisplayScaleMath.mend(holds: false, lastRepair: now.addingTimeInterval(-61), now: now) == .repair)
        print("a mirror holds only in the virtual display's own mode, one repair a minute: ok")

        let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let left = CGRect(x: -3440, y: 0, width: 3440, height: 1440)
        precondition(DisplayScaleMath.origin(of: left, among: [main], width: 2294, height: 960) == CGPoint(x: -2294, y: 0),
                     "the Samsung left of the main monitor at 150% still touches it")
        precondition(DisplayScaleMath.origin(of: left, among: [CGRect(x: -3440, y: -1080, width: 1920, height: 1080), main],
                                             width: 2294, height: 960) == CGPoint(x: -2294, y: 0),
                     "a third display above it does not pull it away from the main one")
        precondition(DisplayScaleMath.origin(of: CGRect(x: 0, y: 1440, width: 3440, height: 1440), among: [main], width: 2294, height: 960)
                     == CGPoint(x: 0, y: 1440), "below the main one: keeps its top edge")
        precondition(DisplayScaleMath.origin(of: CGRect(x: 0, y: -1440, width: 3440, height: 1440), among: [main], width: 2294, height: 960)
                     == CGPoint(x: 0, y: -960), "above the main one: keeps its bottom edge")
        precondition(DisplayScaleMath.origin(of: CGRect(x: 1920, y: 0, width: 3440, height: 1440),
                                             among: [CGRect(x: 5360, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1920, height: 1080)],
                                             width: 2294, height: 960) == CGPoint(x: 1920, y: 0),
                     "between two displays: keeps the edge at the main one")
        precondition(DisplayScaleMath.origin(of: main, among: [left], width: 2294, height: 960) == .zero, "the main display stays at 0,0")
        print("a larger picture keeps the monitor beside the main display: ok")
    }
}
