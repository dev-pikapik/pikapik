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

        precondition(DisplayScaleMath.steps(nativeWidth: 5120, nativeHeight: 2160) == [100, 153, 175, 200],
                     "125% and 150% of 5120x2160 would draw wider than 6720 pixels, so 153% stands in for them")
        precondition(DisplayScaleMath.steps(nativeWidth: 1920, nativeHeight: 1080) == [100, 125, 150, 175], "200% of 1920x1080 would look like 960x540, under 600 points high")
        precondition(DisplayScaleMath.steps(nativeWidth: 6016, nativeHeight: 3384) == [100, 180, 200])
        precondition(DisplayScaleMath.steps(nativeWidth: 3440, nativeHeight: 1440, maxBackingWidth: 5120) == [100, 135, 150, 175, 200],
                     "the HDMI port of a Mac mini M4 takes 5120 pixels: 125% would draw 5504, 135% draws 5096")
        precondition(DisplayScaleMath.steps(nativeWidth: 3440, nativeHeight: 1440, maxBackingWidth: 6144) == [100, 125, 150, 175, 200])
        for pipe in [4096, 5120, 6144] {
            for percent in DisplayScaleMath.steps(nativeWidth: 3440, nativeHeight: 1440, maxBackingWidth: pipe) where percent != 100 {
                let size = DisplayScaleMath.looksLike(nativeWidth: 3440, nativeHeight: 1440, percent: percent)
                precondition(2 * size.width <= pipe && DisplayScaleMath.percent(nativeWidth: 3440, looksLikeWidth: size.width) == percent, "\(percent)% on \(pipe): \(size)")
            }
        }
        for (width, height) in [(3440, 1440), (5120, 2160), (3840, 2160), (2560, 1440), (2560, 1080), (1920, 1080), (6016, 3384), (7680, 4320)] {
            for percent in DisplayScaleMath.steps(nativeWidth: width, nativeHeight: height) {
                let size = DisplayScaleMath.looksLike(nativeWidth: width, nativeHeight: height, percent: percent)
                precondition(size.width % 2 == 0, "\(width)x\(height) at \(percent)% splits evenly at 2x: \(size)")
                precondition(percent == 100 || 2 * size.width <= DisplayScaleMath.maxBackingWidth && size.height >= DisplayScaleMath.minLooksLikeHeight, "\(width)x\(height) at \(percent)%: \(size)")
                precondition(DisplayScaleMath.percent(nativeWidth: width, looksLikeWidth: size.width) == percent, "\(width)x\(height) reads back as \(percent)%: \(size)")
            }
        }
        print("steps a monitor gets, never wider than its pipe: ok")

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

        // Two identical Mi monitors both report serial number 0: their unit numbers tell their virtual displays apart.
        let mi = { (unit: UInt32?, percent: Int) in DisplayScaleMath.serial(vendor: 25001, product: 8193, serial: 0, unit: unit, percent: percent) }
        precondition(mi(nil, 125) == 1_526_297_147, "a Mi alone, as at home, keeps the number macOS knows: \(mi(nil, 125))")
        let twins = ([nil, 0, 1, 2, 3] as [UInt32?]).flatMap { unit in DisplayScaleMath.steps.map { mi(unit, $0) } }
        precondition(Set(twins).count == twins.count && !twins.contains(0), "every unit and step gets its own number: \(twins)")
        precondition(!DisplayScaleMath.steps.contains { DisplayScaleMath.serial(vendor: 19501, product: 29455, serial: 810432311, unit: 1, percent: $0) == 810432311 },
                     "a twin's virtual display never takes the monitor's own number")
        let isMi = { (serial: UInt32, unit: UInt32) in DisplayScaleMath.isVirtual(serial, vendor: 25001, product: 8193, serial: 0, unit: unit) }
        precondition(isMi(mi(1, 125), 1) && !isMi(mi(1, 125), 2), "a twin's virtual display belongs to its own monitor only")
        precondition(isMi(mi(nil, 125), 7), "the virtual display made before the twin came still belongs to the monitor")
        precondition(DisplayScaleMath.isVirtual(samsung(150), vendor: 19501, product: 29455, serial: 810432311, unit: 3), "a monitor without a twin keeps its virtual displays")
        precondition(!isMi(0, 2) && !DisplayScaleMath.isVirtual(810432311, vendor: 19501, product: 29455, serial: 810432311, unit: 3),
                     "a monitor is never taken for a virtual display of its twin or of itself")
        print("identical monitors get virtual displays of their own: ok")

        let kept = ["25001-8193-0-1": 125, "25001-8193-0-2": 150, "25001-8193-0": 100, "19501-29455-810432311": 175]
        precondition(DisplayScaleMath.twinSize(saved: kept, key: "25001-8193-0", online: ["25001-8193-0-2", "25001-8193-0-4"]) == 125,
                     "a twin numbered anew takes the larger size its model has under an id not in use, never its twin's or another model's")
        precondition(DisplayScaleMath.twinSize(saved: ["25001-8193-0-2": 150], key: "25001-8193-0", online: ["25001-8193-0-2", "25001-8193-0-4"]) == nil,
                     "the size of the twin that is there stays its own")
        precondition(DisplayScaleMath.twinSize(saved: ["25001-8193-12": 200, "25001-8193-1-3": 125], key: "25001-8193-1", online: []) == 125,
                     "serial number 12 is another monitor, not a twin of serial number 1")
        print("a twin numbered anew keeps a saved size: ok")

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

        // Two identical 3440x1440 monitors side by side at 125% (2752x1152 points), the left one main.
        let twin125 = CGRect(x: 0, y: 0, width: 2752, height: 1152), right125 = CGRect(x: 2752, y: 0, width: 2752, height: 1152)
        var arranged = DisplayScaleMath.arrange(twin125, among: [right125], width: 2294, height: 960)
        precondition(arranged.here == .zero && arranged.others == [CGPoint(x: 2294, y: 0)],
                     "the main monitor at 150%: the one right of it moves 458 points left and still touches it: \(arranged)")
        let main150 = CGRect(x: 0, y: 0, width: 2294, height: 960)
        arranged = DisplayScaleMath.arrange(CGRect(x: 2294, y: 0, width: 2752, height: 1152), among: [main150], width: 2294, height: 960)
        precondition(arranged.here == CGPoint(x: 2294, y: 0) && arranged.others == [.zero], "then the right one at 150%: \(arranged)")
        arranged = DisplayScaleMath.arrange(main150, among: [CGRect(x: 2294, y: 0, width: 2294, height: 960)], width: 2752, height: 1152)
        precondition(arranged.others == [CGPoint(x: 2752, y: 0)], "the main one back at 125%: the right one moves back: \(arranged)")
        arranged = DisplayScaleMath.arrange(CGRect(x: -2752, y: 0, width: 2752, height: 1152), among: [twin125], width: 2294, height: 960)
        precondition(arranged.here == CGPoint(x: -2294, y: 0) && arranged.others == [.zero], "the Samsung left of the main Mi at 150%: \(arranged)")
        let beyond = [CGRect(x: -2752, y: 0, width: 2752, height: 1152), right125, CGRect(x: 0, y: 1152, width: 1920, height: 1080),
                      CGRect(x: 0, y: -1080, width: 1920, height: 1080)]
        arranged = DisplayScaleMath.arrange(twin125, among: beyond, width: 2294, height: 960)
        precondition(arranged.others == [CGPoint(x: -2752, y: 0), CGPoint(x: 2294, y: 0), CGPoint(x: 0, y: 960), CGPoint(x: 0, y: -1080)],
                     "only the displays beyond the edges that move move with them: \(arranged)")
        print("every display still touches the ones it touched after a size change: ok")
    }
}
