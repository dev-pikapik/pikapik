import SwiftUI

/// A monitor in its panel's own shape with a small desktop on it, drawn the way it looks at `percent`: at 150% the
/// menu bar, the window, its text and the Dock are half as large again, and less of them fits.
struct DisplayScalePreview: View {
    let nativeWidth: Int
    let nativeHeight: Int
    let percent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let panel = CGSize(width: max(nativeWidth, 1), height: max(nativeHeight, 1))
        Miniature(panel: panel, zoom: CGFloat(max(percent, 1)) / 100)
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12), value: percent)
            .aspectRatio(Miniature.aspect(of: panel), contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct Miniature: View, Animatable {
    let panel: CGSize
    var zoom: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var direction

    nonisolated var animatableData: CGFloat {
        get { zoom }
        set { zoom = newValue }
    }

    // The monitor around the screen, in screen heights.
    private static let bezel: CGFloat = 0.03
    private static let chin: CGFloat = 0.05
    private static let neck = CGSize(width: 0.16, height: 0.12)
    private static let foot = CGSize(width: 0.7, height: 0.04)
    private static let height = 1 + bezel + chin + neck.height + foot.height

    static func aspect(of panel: CGSize) -> CGFloat {
        (panel.width / panel.height + 2 * bezel) / height
    }

    var body: some View {
        Canvas { context, size in
            let dark = scheme == .dark
            let ratio = panel.width / panel.height
            let unit = min(size.height / Self.height, size.width / (ratio + 2 * Self.bezel))
            let bezel = Self.bezel * unit
            let frame = CGRect(x: (size.width - ratio * unit - 2 * bezel) / 2, y: (size.height - Self.height * unit) / 2,
                               width: ratio * unit + 2 * bezel, height: unit + bezel + Self.chin * unit)
            drawStand(in: context, under: frame, unit: unit, dark: dark)
            let shape = Path(roundedRect: frame, cornerRadius: bezel * 1.2, style: .continuous)
            context.fill(shape, with: .color(Self.rgb(0x1D1D1F)))
            if dark {
                context.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: bezel * 1.2, style: .continuous),
                               with: .color(.white.opacity(0.14)), lineWidth: 1)
            }
            let screen = CGRect(x: frame.minX + bezel, y: frame.minY + bezel, width: ratio * unit, height: unit)
            var desk = context
            desk.clip(to: Path(roundedRect: screen, cornerRadius: bezel * 0.3))
            Desk(screen: screen, size: CGSize(width: panel.width / zoom, height: panel.height / zoom),
                 rtl: direction == .rightToLeft, dark: dark).draw(in: desk)
        }
    }

    private func drawStand(in context: GraphicsContext, under frame: CGRect, unit: CGFloat, dark: Bool) {
        let neck = CGRect(x: frame.midX - Self.neck.width * unit / 2, y: frame.maxY - 1, width: Self.neck.width * unit, height: Self.neck.height * unit + 1)
        let foot = CGRect(x: frame.midX - Self.foot.width * unit / 2, y: neck.maxY - 0.5, width: Self.foot.width * unit, height: Self.foot.height * unit)
        var shadow = context
        shadow.addFilter(.blur(radius: foot.height * 0.8))
        shadow.fill(Path(ellipseIn: foot.insetBy(dx: -foot.width * 0.04, dy: 0).offsetBy(dx: 0, dy: foot.height * 0.6)),
                    with: .color(.black.opacity(dark ? 0.5 : 0.18)))
        let down = { (rect: CGRect, colors: [UInt32]) in
            GraphicsContext.Shading.linearGradient(Gradient(colors: colors.map(Self.rgb)), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY))
        }
        context.fill(Path(neck), with: down(neck, dark ? [0x26272B, 0x46484D] : [0x8C9097, 0xC3C6CC]))
        context.fill(Path(roundedRect: foot, cornerRadius: foot.height / 2), with: down(foot, dark ? [0x56595F, 0x37393E] : [0xDCDEE2, 0xA7AAB1]))
    }

    nonisolated static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The desktop on the screen. Everything is laid out in the points the desktop has at this size and drawn `scale`
/// times smaller, so a larger size draws the same things larger.
private struct Desk {
    let screen: CGRect
    let size: CGSize
    let rtl: Bool
    let dark: Bool

    private var scale: CGFloat { screen.width / size.width }
    private var ink: Color { dark ? .white : .black }

    private static let window = CGRect(x: 200, y: 90, width: 1040, height: 640)
    private static let menuBar: CGFloat = 34
    private static let icon: CGFloat = 70
    private static let dockIcons: [[UInt32]] = [
        [0x6CC4FF, 0x0A7AFF], [0x86E39A, 0x2DB84F], [0xFFC870, 0xFF8A00], [0xFF8DA1, 0xFF2D55],
        [0xC9A2FF, 0x9B4FE0], [0x7BE6DF, 0x1FA9C2], [0xFFE58A, 0xFFC200], [0xD8D8DE, 0x8E8E95],
    ]

    /// A rectangle in desktop points, placed on the screen; right to left, it is mirrored like macOS mirrors its desktop.
    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: screen.minX + (rtl ? size.width - x - width : x) * scale, y: screen.minY + y * scale, width: width * scale, height: height * scale)
    }

    private func pill(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        Path(roundedRect: rect(x, y, width, height), cornerRadius: height * scale / 2)
    }

    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius * scale, style: .continuous)
    }

    func draw(in context: GraphicsContext) {
        let wallpaper: [UInt32] = dark ? [0x1C2849, 0x3D2C5E] : [0x8FB9FF, 0xD9C7FF]
        context.fill(Path(screen), with: .linearGradient(Gradient(colors: wallpaper.map(Miniature.rgb)),
                                                          startPoint: CGPoint(x: screen.minX, y: screen.minY), endPoint: CGPoint(x: screen.maxX, y: screen.maxY)))
        context.fill(Path(screen), with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.08 : 0.3), .white.opacity(0)]),
                                                          center: CGPoint(x: screen.minX + screen.width * 0.28, y: screen.minY + screen.height * 0.2),
                                                          startRadius: 0, endRadius: screen.width * 0.6))
        drawFolders(in: context)
        drawWindow(in: context)
        drawMenuBar(in: context)
        drawDock(in: context)
    }

    private func drawFolders(in context: GraphicsContext) {
        let x = size.width - 44 - 76
        for y in [CGFloat(64), 190] {
            context.fill(rounded(rect(x + 4, y, 30, 16), 4), with: .color(Miniature.rgb(0x3E9CF0)))
            let body = rect(x, y + 8, 76, 54)
            context.fill(rounded(body, 7), with: .linearGradient(Gradient(colors: [Miniature.rgb(0x8FCDFF), Miniature.rgb(0x52ABF6)]),
                                                                 startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY)))
            context.fill(pill(x + 8, y + 74, 60, 10), with: .color(ink.opacity(dark ? 0.7 : 0.4)))
        }
    }

    private func drawWindow(in context: GraphicsContext) {
        let origin = Self.window.origin
        let frame = rect(origin.x, origin.y, Self.window.width, Self.window.height)
        let shape = rounded(frame, 22)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 30 * scale, y: 12 * scale))
            layer.fill(shape, with: .color(dark ? Miniature.rgb(0x262629) : .white))
        }
        context.stroke(shape, with: .color(dark ? .white.opacity(0.12) : .black.opacity(0.08)), lineWidth: 0.5)
        var inside = context
        inside.clip(to: shape)
        inside.fill(rounded(rect(origin.x + 10, origin.y + 10, 250, 620), 16), with: .color(ink.opacity(dark ? 0.06 : 0.045)))
        for (index, color) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            inside.fill(Path(ellipseIn: rect(origin.x + 28 + CGFloat(index) * 27, origin.y + 25, 17, 17)), with: .color(Miniature.rgb(color)))
        }
        for (index, width) in [CGFloat(120), 96, 132, 88, 110].enumerated() {
            let y = origin.y + 92 + CGFloat(index) * 46
            if index == 0 {
                inside.fill(rounded(rect(origin.x + 20, y - 11, 230, 38), 10), with: .color(Color.accentColor.opacity(dark ? 0.35 : 0.2)))
            }
            inside.fill(rounded(rect(origin.x + 36, y, 16, 16), 4), with: .color(Color.accentColor.opacity(0.85)))
            inside.fill(pill(origin.x + 64, y + 3, width, 10), with: .color(ink.opacity(dark ? 0.45 : 0.35)))
        }
        let left = origin.x + 300
        inside.fill(pill(left, origin.y + 27, 170, 14), with: .color(ink.opacity(dark ? 0.7 : 0.65)))
        let sample = inside.resolve(Text(verbatim: "Aa").font(.system(size: 120 * scale, weight: .semibold)).foregroundStyle(ink.opacity(dark ? 0.92 : 0.85)))
        let measured = sample.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
        inside.draw(sample, in: rect(left, origin.y + 82, measured.width / scale, measured.height / scale))
        let lines: [(y: CGFloat, width: CGFloat)] = [(270, 700), (310, 660), (350, 690), (390, 630), (430, 380), (490, 680), (530, 700), (570, 470)]
        for line in lines {
            inside.fill(pill(left, origin.y + line.y, line.width, 14), with: .color(ink.opacity(dark ? 0.24 : 0.17)))
        }
    }

    private func drawMenuBar(in context: GraphicsContext) {
        context.fill(Path(rect(0, 0, size.width, Self.menuBar)), with: .color(dark ? .black.opacity(0.22) : .white.opacity(0.4)))
        context.fill(Path(ellipseIn: rect(26, 9, 16, 16)), with: .color(ink.opacity(0.8)))
        context.fill(pill(62, 12, 64, 10), with: .color(ink.opacity(0.75)))
        var x: CGFloat = 152
        for width in [CGFloat(44), 36, 42, 50, 40] {
            context.fill(pill(x, 12, width, 10), with: .color(ink.opacity(0.45)))
            x += width + 24
        }
        let clock = size.width - 26 - 92
        context.fill(pill(clock, 12, 92, 10), with: .color(ink.opacity(0.6)))
        for index in 0..<3 {
            context.fill(Path(ellipseIn: rect(clock - 40 - CGFloat(index) * 36, 10, 14, 14)), with: .color(ink.opacity(0.5)))
        }
    }

    private func drawDock(in context: GraphicsContext) {
        let gap: CGFloat = 12, padding: CGFloat = 12
        let width = CGFloat(Self.dockIcons.count) * (Self.icon + gap) - gap + 2 * padding
        let height = Self.icon + 2 * padding
        let x = (size.width - width) / 2, y = size.height - 10 - height
        let dock = rounded(rect(x, y, width, height), 28)
        context.fill(dock, with: .color(.white.opacity(dark ? 0.14 : 0.45)))
        context.stroke(dock, with: .color(.white.opacity(dark ? 0.2 : 0.65)), lineWidth: 0.5)
        for (index, colors) in Self.dockIcons.enumerated() {
            let icon = rect(x + padding + CGFloat(index) * (Self.icon + gap), y + padding, Self.icon, Self.icon)
            context.fill(rounded(icon, 16), with: .linearGradient(Gradient(colors: colors.map(Miniature.rgb)),
                                                                  startPoint: CGPoint(x: icon.midX, y: icon.minY), endPoint: CGPoint(x: icon.midX, y: icon.maxY)))
        }
    }
}
