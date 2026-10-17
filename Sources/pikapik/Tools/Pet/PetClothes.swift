import SwiftUI

struct PetClothes {
    enum Layer: CaseIterable { case back, feet, base, legs, outer, neck, prop, whiskers, face, head, glass }

    let pose: PetPose, night: Bool, body: Path, width: CGFloat, height: CGFloat, eye: CGPoint, paws: [CGRect], ground: CGFloat, place: CGAffineTransform
    var outlined = true

    func draw(_ layer: Layer, _ fill: (Path, Color) -> Void) {
        let layers = shapes(layer)
        if layer == .back { outline(layers, fill) }
        for (path, paint) in layers { fill(path.applying(place), paint.color) }
    }

    func outline(_ fill: (Path, Color) -> Void) { outline(Self.front.flatMap(shapes), fill) }

    static let rim = Color(red: 0.48, green: 0.50, blue: 0.58)

    static let stroke = StrokeStyle(lineWidth: 0.7, lineJoin: .round)

    private static let grounds = [1.0, 30.0 / 255]

    private static func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    static func faint(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Bool {
        grounds.contains { ground in
            let l = 0.2126 * linear(a * r + (1 - a) * ground) + 0.7152 * linear(a * g + (1 - a) * ground) + 0.0722 * linear(a * b + (1 - a) * ground), back = linear(ground)
            return (max(l, back) + 0.05) / (min(l, back) + 0.05) < 3
        }
    }

    private static let front = Layer.allCases.filter { $0 != .back }

    private func outline(_ layers: Layers, _ fill: (Path, Color) -> Void) {
        guard outlined else { return }
        var faint: [(path: Path, box: CGRect)] = []
        var covers = [body.boundingRect.insetBy(dx: 2, dy: 2)]
        for (path, paint) in layers {
            let box = path.boundingRect
            if paint.faint && !paint.nested && !covers.contains(where: { $0.contains(box) }) {
                for part in path.subpaths {
                    let inner = part.boundingRect
                    let holders = faint.filter { $0.box.contains(inner) }, probes = holders.isEmpty ? [] : part.inside
                    if !holders.contains(where: { held in probes.allSatisfy { held.path.contains($0) } }) { faint.append((part, inner)) }
                }
            }
            var parts = 0
            path.forEach { if case .move = $0 { parts += 1 } }
            if parts == 1 { covers.append(box) }
        }
        for part in faint { fill(part.path.strokedPath(Self.stroke).applying(place), Self.rim) }
    }

    typealias Ink = (r: Double, g: Double, b: Double)
    struct Paint {
        let color: Color, ink: Ink, alpha: Double, nested: Bool
        var faint: Bool { PetClothes.faint(ink.r, ink.g, ink.b, alpha) }
    }
    typealias Layers = [(Path, Paint)]

    enum Dye {
        static let ink: Ink = (0.15, 0.14, 0.19), satin: Ink = (0.30, 0.28, 0.37)
        static let white: Ink = (0.98, 0.97, 0.95), cream: Ink = (0.98, 0.93, 0.80), mist: Ink = (0.78, 0.80, 0.87)
        static let navy: Ink = (0.18, 0.23, 0.42), midnight: Ink = (0.16, 0.19, 0.36)
        static let denim: Ink = (0.33, 0.50, 0.74), denimDeep: Ink = (0.23, 0.37, 0.60), denimLight: Ink = (0.58, 0.72, 0.92)
        static let blue: Ink = (0.30, 0.53, 0.87), blueDeep: Ink = (0.20, 0.37, 0.68)
        static let mustard: Ink = (0.93, 0.70, 0.22), mustardDeep: Ink = (0.77, 0.53, 0.12)
        static let yellow: Ink = (1.0, 0.83, 0.26), yellowDeep: Ink = (0.85, 0.61, 0.12)
        static let gold: Ink = (0.98, 0.78, 0.29), goldDeep: Ink = (0.80, 0.56, 0.15)
        static let sage: Ink = (0.60, 0.74, 0.60), sageDeep: Ink = (0.45, 0.59, 0.47), leaf: Ink = (0.48, 0.70, 0.46)
        static let lavender: Ink = (0.76, 0.68, 0.94), lavenderDeep: Ink = (0.58, 0.50, 0.84)
        static let violet: Ink = (0.50, 0.36, 0.78), violetDeep: Ink = (0.37, 0.25, 0.62)
        static let purple: Ink = (0.45, 0.32, 0.72), purpleDeep: Ink = (0.31, 0.21, 0.53)
        static let pink: Ink = (0.98, 0.66, 0.78), pinkDeep: Ink = (0.93, 0.47, 0.65), blush: Ink = (0.99, 0.82, 0.88)
        static let turquoise: Ink = (0.24, 0.74, 0.74), turquoiseDeep: Ink = (0.14, 0.55, 0.57)
        static let tan: Ink = (0.84, 0.64, 0.42), tanDeep: Ink = (0.64, 0.45, 0.28), brown: Ink = (0.37, 0.25, 0.18), oat: Ink = (0.82, 0.71, 0.53)
        static let steel: Ink = (0.68, 0.72, 0.80), steelDeep: Ink = (0.50, 0.54, 0.64), silver: Ink = (0.86, 0.87, 0.91)
        static let bronze: Ink = (0.80, 0.60, 0.32), bronzeDeep: Ink = (0.58, 0.40, 0.20), ivory: Ink = (0.97, 0.93, 0.82)
        static let indigo: Ink = (0.29, 0.33, 0.66), indigoDeep: Ink = (0.20, 0.23, 0.50)
        static let glass: Ink = (0.80, 0.90, 1.0), string: Ink = (0.36, 0.40, 0.48), feather: Ink = (0.87, 0.88, 0.95)
        static let shade: Ink = (0.10, 0.08, 0.20), snow: Ink = (0.90, 0.91, 0.95)
        static let chestnut: Ink = (0.58, 0.33, 0.19), chestnutDeep: Ink = (0.40, 0.21, 0.12)
        static let pine: Ink = (0.16, 0.45, 0.43), pineDeep: Ink = (0.10, 0.31, 0.31)
    }

    func c(_ k: Ink, _ a: Double = 1, nested: Bool = false) -> Paint {
        let l = night ? 0.12 : 0
        let ink = (k.r + (1 - k.r) * l, k.g + (1 - k.g) * l, k.b + (1 - k.b) * l)
        return Paint(color: Color(red: ink.0, green: ink.1, blue: ink.2, opacity: a), ink: ink, alpha: a, nested: nested)
    }

    var neck: CGFloat { -height / 2 + 6.4 }
    var chest: CGFloat { -height / 2 + 5.7 }
    var waist: CGFloat { height / 2 - 2.6 }
    var half: CGFloat { width / 2 }
    var sealed: Bool { pose.outfit[.head] == .helmet }
    var walk: CGFloat { pose.air ? 0 : 1 - pose.sit }

    private final class Memo { var layers: [Layer: Layers] = [:] }
    private let memo = Memo()

    private func shapes(_ layer: Layer) -> Layers {
        if let hit = memo.layers[layer] { return hit }
        let built = build(layer).map { (Path($0.0.cgPath), $0.1) }
        memo.layers[layer] = built
        return built
    }

    private func build(_ layer: Layer) -> Layers {
        let o = pose.outfit
        switch layer {
        case .back: return o[.back].map { inside(back($0)) } ?? []
        case .feet: return o[.feet].map(shoes) ?? []
        case .base, .outer:
            guard let item = o[.body], [.hoodie, .labcoat, .tux, .tailcoat, .tweed].contains(item) == (layer == .outer) else { return [] }
            return top(item)
        case .legs: return o[.legs].map(legs) ?? []
        case .neck: return (o[.back] == .cape ? collar : []) + (o[.neck].map(scarf) ?? [])
        case .prop: return o[.back] == .cane ? cane : []
        case .whiskers: return o[.whiskers].map(moustache) ?? []
        case .face: return o[.face].map(face) ?? []
        case .head:
            guard let item = o[.head] else { return [] }
            if item == .helmet { return dome }
            let fit = CGAffineTransform(scaleX: width / 12, y: height / 11).concatenating(CGAffineTransform(translationX: 0, y: -height / 2))
            return hat(item).map { ($0.0.applying(fit), $0.1) }
        case .glass: return o[.head] == .helmet ? glass : []
        }
    }

    private func hat(_ item: PetItem) -> Layers {
        let s = CGFloat(pose.step)
        switch item {
        case .cap:
            var blue = blob([P(-6.3, 2.2), P(-6.0, -0.3), P(-4.4, -1.9), P(-1.4, -2.6), P(1.9, -2.4), P(4.6, -1.2), P(6.1, 0.8), P(6.0, 1.9), P(0, 2.1)])
            blue.addPath(blob([P(3.6, 0.9), P(7.3, 0.8), P(9.8, 1.4), P(10.0, 2.1), P(7.3, 2.0), P(3.6, 2.0)]))
            var deep = ribbon(trace([P(4.4, 1.75), P(7.3, 1.75), P(9.85, 1.95)]), { _ in 0.6 })
            deep.addPath(ribbon(trace([P(-0.6, -2.4), P(2.4, -1.6), P(4.4, 0.6)]), { _ in 0.5 }))
            deep.addPath(ribbon(trace([P(-0.6, -2.4), P(-3.5, -1.5), P(-5.3, 0.9)]), { _ in 0.5 }))
            deep.addPath(oval(-0.6, -2.55, 0.8, 0.45))
            let shine = blob([P(-5.0, -0.2), P(-3.8, -1.4), P(-1.8, -2.0), P(-1.6, -1.6), P(-3.5, -0.8)])
            return [(blue, c(Dye.blue)), (deep, c(Dye.blueDeep)), (shine, c(Dye.white, 0.25))]
        case .beanie:
            var knit = blob([P(-6.0, 1.2), P(-5.7, -1.4), P(-3.8, -3.1), P(-0.6, -3.7), P(2.8, -3.3), P(5.3, -1.6), P(6.0, 1.2)])
            let cuff = trace([P(-6.3, 1.2), P(0, 1.5), P(6.2, 1.15)])
            knit.addPath(ribbon(cuff, { _ in 2.0 }))
            var ribs = ribbon(trace([P(-6.0, 0.15), P(0, 0.45), P(6.0, 0.1)]), { _ in 0.45 })
            for k in 0..<10 {
                let x = -5.1 + CGFloat(k) * 1.15, y = 1.2 + 0.3 * (1 - x * x / 40)
                ribs.addPath(Path(roundedRect: CGRect(x: x - 0.25, y: y - 0.7, width: 0.5, height: 1.5), cornerRadius: 0.25))
            }
            let shine = blob([P(-4.6, -1.0), P(-3.4, -2.4), P(-1.4, -3.0), P(-1.2, -2.5), P(-3.0, -1.6)])
            return [(knit, c(Dye.mustard)), (ribs, c(Dye.mustardDeep)), (shine, c(Dye.white, 0.25)), (fluff(P(-0.3, -4.3), 1.6), c(Dye.cream))]
        case .party:
            let lean = CGAffineTransform(translationX: 0, y: -1.2).concatenating(CGAffineTransform(rotationAngle: -0.2)).concatenating(CGAffineTransform(translationX: 0, y: 1.2))
            let cone = poly(trace([P(-2.9, 1.0), P(0, 1.65), P(2.9, 1.0)], 4) + [P(0.25, -6.6), P(-0.25, -6.6)])
            var bands = Path()
            for k in 0..<3 { bands.addPath(poly([P(-4, -0.6 - CGFloat(k) * 2.6), P(4, -2.4 - CGFloat(k) * 2.6), P(4, -1.3 - CGFloat(k) * 2.6), P(-4, 0.5 - CGFloat(k) * 2.6)])) }
            let side = poly([P(0.1, -6.4), P(2.9, 1.0), P(1.6, 1.45)])
            return [(cone.applying(lean), c(Dye.pink)), (bands.intersection(cone).applying(lean), c(Dye.white, nested: true)), (side.applying(lean), c(Dye.shade, 0.12)), (fluff(P(0, -6.9), 1.2).applying(lean), c(Dye.gold))]
        case .flowers:
            var petals = [Path(), Path(), Path()], hearts = Path(), leaves = Path()
            let xs: [CGFloat] = [-5.6, -3.8, -1.9, 0.1, 2.1, 4.0, 5.6]
            for (i, x) in xs.enumerated() {
                let y = 0.2 + 0.05 * x * x, r: CGFloat = i % 2 == 0 ? 1.25 : 1.05
                for k in 0..<5 {
                    let a = CGFloat(k) * 2 * .pi / 5 + CGFloat(i) * 0.7
                    petals[i % 3].addPath(oval(x + cos(a) * r * 0.55, y + sin(a) * r * 0.55, r * 0.5, r * 0.5))
                }
                hearts.addPath(oval(x, y, r * 0.36, r * 0.36))
                if i < xs.count - 1 {
                    let m = (x + xs[i + 1]) / 2
                    leaves.addPath(oval(m, 0.95 + 0.05 * m * m, 0.45, 0.95).turned(i % 2 == 0 ? 0.9 : -0.9, P(m, 0.95 + 0.05 * m * m)))
                }
            }
            return [(leaves, c(Dye.leaf)), (petals[0], c(Dye.pink)), (petals[1], c(Dye.lavender)), (petals[2], c(Dye.white)), (hearts, c(Dye.gold, nested: true))]
        case .bunny:
            let bounce = pose.air ? -0.3 : 0.1 * sin(2 * s - 0.6) * walk
            let back = ear(P(-2.2, 0.4), -0.34 + bounce, 0, 7.0), front = ear(P(0.9, 0.2), 0.14 + bounce * 1.3, 0.9 + bounce, 7.2)
            let band = ribbon(trace([P(-5.6, 2.4), P(-4.6, 0.6), P(-2.5, -0.25), P(0, -0.4), P(2.5, -0.25), P(4.6, 0.6), P(5.6, 2.4)]), { _ in 0.9 })
            var deep = back.0
            deep.addPath(band)
            return [(deep, c(Dye.lavenderDeep)), (back.1, c(Dye.pinkDeep)), (front.0, c(Dye.lavender)), (front.1, c(Dye.pink))]
        case .cowboy:
            var tan = blob([P(-3.5, 0.9), P(-3.3, -2.0), P(-2.9, -4.0), P(-1.6, -4.6), P(-0.2, -4.0), P(1.2, -4.6), P(2.6, -4.1), P(3.2, -2.0), P(3.5, 0.9)])
            tan.addPath(blob([P(-8.6, -0.7), P(-6.4, 0.4), P(-3.4, 0.95), P(0, 1.05), P(3.4, 0.95), P(6.4, 0.4), P(8.6, -0.7), P(8.3, 0.4), P(5.6, 1.7), P(0, 2.3), P(-5.6, 1.7), P(-8.3, 0.4)]))
            let band = poly([P(-3.42, -0.5), P(3.42, -0.5), P(3.45, 0.98), P(0, 1.08), P(-3.45, 0.98)])
            let under = ribbon(trace([P(-8.0, 0.35), P(-5.6, 1.45), P(0, 2.0), P(5.6, 1.45), P(8.0, 0.35)]), { _ in 0.6 })
            let shine = blob([P(-2.5, -3.7), P(-1.9, -4.1), P(-1.6, -1.2), P(-2.3, -0.9)])
            return [(tan, c(Dye.tan)), (band, c(Dye.brown)), (under, c(Dye.tanDeep)), (shine, c(Dye.white, 0.22))]
        case .tophat:
            let lean = CGAffineTransform(translationX: 0, y: -1.0).concatenating(CGAffineTransform(rotationAngle: -0.08)).concatenating(CGAffineTransform(translationX: 0, y: 1.0))
            var ink = poly([P(-3.0, 0.7), P(-2.9, -3.0), P(-3.3, -6.6), P(3.3, -6.6), P(2.9, -3.0), P(3.0, 0.7)])
            ink.addPath(blob([P(-5.3, -0.3), P(-3.0, 0.35), P(0, 0.5), P(3.0, 0.35), P(5.3, -0.3), P(5.1, 0.45), P(2.9, 1.25), P(0, 1.4), P(-2.9, 1.25), P(-5.1, 0.45)]))
            let band = poly([P(-2.96, -1.6), P(2.96, -1.6), P(3.0, 0.4), P(-3.0, 0.4)])
            let shine = poly([P(-2.3, -6.2), P(-1.4, -6.2), P(-1.35, -1.9), P(-2.15, -1.9)])
            return [(ink.applying(lean), c(Dye.ink)), (band.applying(lean), c(Dye.violet)), (shine.applying(lean), c(Dye.white, 0.16))]
        case .detective:
            var cap = blob([P(-6.2, 2.0), P(-6.0, -0.4), P(-4.3, -2.1), P(-1.4, -2.8), P(1.7, -2.7), P(4.4, -1.8), P(6.0, 0.2), P(6.1, 2.0), P(0, 2.2)])
            cap.addPath(blob([P(3.8, 1.3), P(6.6, 1.3), P(8.6, 2.2), P(8.5, 2.9), P(6.2, 2.7), P(3.8, 2.4)]))
            cap.addPath(blob([P(-3.8, 1.3), P(-6.6, 1.4), P(-8.5, 2.4), P(-8.3, 3.1), P(-6.0, 2.8), P(-3.8, 2.5)]))
            var v = Path(), h = Path()
            for k in 0..<10 { v.addRect(CGRect(x: -8.4 + CGFloat(k) * 1.8, y: -3.2, width: 0.6, height: 6.6)) }
            for k in 0..<4 { h.addRect(CGRect(x: -9, y: -2.3 + CGFloat(k) * 1.6, width: 18, height: 0.6)) }
            var dark = ribbon(trace([P(-6.0, 1.95), P(0, 2.15), P(6.0, 1.95)]), { _ in 0.5 })
            dark.addPath(oval(-0.9, -3.0, 0.8, 0.45).turned(0.3, P(-0.9, -3.0)))
            dark.addPath(oval(0.9, -3.0, 0.8, 0.45).turned(-0.3, P(0.9, -3.0)))
            dark.addPath(oval(0, -2.85, 0.45, 0.45))
            return [(cap, c(Dye.oat)), (v.intersection(cap), c(Dye.brown, 0.32, nested: true)), (h.intersection(cap), c(Dye.brown, 0.32, nested: true)), (dark, c(Dye.brown))]
        case .pirate:
            let edge = [P(-7.5, -0.2), P(-6.1, -2.0), P(-3.8, -3.4), P(-1.7, -3.0), P(0.7, -4.4), P(2.9, -3.5), P(5.0, -3.4), P(6.9, -1.6), P(7.8, 0.5)]
            let shape = blob(edge + [P(5.2, 1.5), P(1.0, 2.1), P(-3.2, 1.7), P(-6.3, 0.9)])
            let trim = ribbon(trace(edge), { _ in 0.7 })
            let shine = blob([P(-4.6, -2.2), P(-2.4, -2.4), P(-2.6, -1.8), P(-4.4, -1.6)])
            return [(shape, c(Dye.ink)), (trim, c(Dye.gold)), (shine, c(Dye.white, 0.18))]
        case .propeller:
            let r: CGFloat = 6.2, h: CGFloat = 4.6, base: CGFloat = 1.9
            func meridian(_ a: CGFloat, _ up: Bool) -> [CGPoint] {
                (0...6).map { k in let t = CGFloat(up ? k : 6 - k) / 6 * .pi / 2; return P(r * cos(t) * sin(a), base - h * sin(t)) }
            }
            let dome = poly(meridian(-.pi / 2, true) + meridian(.pi / 2, false))
            var gores = Path()
            for (a, b) in [(-70.0, -10.0), (50.0, 90.0)] { gores.addPath(poly(meridian(a * .pi / 180, true) + meridian(b * .pi / 180, false))) }
            var navy = ribbon(trace([P(-6.1, 1.5), P(0, 1.7), P(6.1, 1.5)]), { _ in 0.8 })
            navy.addPath(Path(CGRect(x: -0.3, y: -4.0, width: 0.6, height: 1.5)))
            let spin = s * 1.7 + pose.lift * 0.6, reach = 1.75 * cos(spin)
            var blades = oval(reach, -4.25, abs(reach) + 0.35, 0.5 + 0.15 * abs(sin(spin)))
            blades.addPath(oval(-reach, -4.25, abs(reach) + 0.35, 0.5 + 0.15 * abs(sin(spin))))
            return [(dome, c(Dye.turquoise)), (gores, c(Dye.mustard)), (navy, c(Dye.navy)), (blades, c(Dye.pink)), (oval(0, -4.25, 0.5, 0.5), c(Dye.navy))]
        case .wizard:
            let sway = (pose.air ? 0.6 : 0.25 * sin(s * 2)) * (1 - pose.sit)
            let line = trace([P(0, 1.0), P(-0.3, -2.5), P(-0.8, -5.2), P(-1.9 - sway, -6.9), P(-3.8 - sway, -6.4 + sway)], 5)
            var cone = ribbon(line, { 6.6 * pow(1 - $0, 1.15) + 0.5 })
            cone.addPath(oval(line[line.count - 1].x, line[line.count - 1].y, 0.3, 0.3))
            let lip = poly((0...12).map { k in let t = CGFloat(k) / 12 * .pi; return P(7.0 * cos(t), 1.0 + 1.15 * sin(t)) })
            var purple = cone
            purple.addPath(lip)
            var stars = star(P(0.9, -1.9), 1.05)
            stars.addPath(star(P(-1.3, -4.5), 0.75))
            stars.addPath(star(P(2.1, -0.1), 0.55))
            let side = ribbon(Array(line.prefix(line.count * 2 / 3)), { 1.6 * (1 - $0) + 0.3 }).offsetBy(dx: 2.0, dy: 0).intersection(cone)
            return [(oval(0, 1.0, 7.0, 1.15), c(Dye.purpleDeep)), (purple, c(Dye.purple)), (side, c(Dye.shade, 0.16, nested: true)), (stars, c(Dye.gold))]
        case .viking:
            var horns = Path()
            for d in [-1.0, 1.0] as [CGFloat] {
                let line = trace([P(4.3 * d, 0.4), P(6.5 * d, -0.6), P(8.0 * d, -2.7), P(8.2 * d, -5.2)])
                horns.addPath(ribbon(line, { 1.9 * (1 - $0) + 0.3 }))
            }
            let dome = blob([P(-6.1, 1.9), P(-5.6, -0.6), P(-3.6, -2.2), P(0, -2.6), P(3.6, -2.2), P(5.6, -0.6), P(6.1, 1.9)])
            var bronze = ribbon(trace([P(-6.1, 1.3), P(0, 1.55), P(6.1, 1.3)]), { _ in 1.3 })
            bronze.addPath(ribbon(trace([P(-0.6, 1.0), P(-0.4, -1.4), P(-0.1, -2.6)]), { _ in 1.0 }))
            var rivets = Path()
            for x in [-4.6, -2.6, 1.6, 3.8] as [CGFloat] { rivets.addPath(oval(x, 1.35 + 0.006 * x * x, 0.3, 0.3)) }
            rivets.addPath(oval(-0.45, -0.6, 0.28, 0.28))
            let shine = blob([P(-4.6, -0.6), P(-3.4, -1.7), P(-1.6, -2.1), P(-1.5, -1.6), P(-3.2, -1.0)])
            return [(horns, c(Dye.ivory)), (dome, c(Dye.steel)), (shine, c(Dye.white, 0.3)), (bronze, c(Dye.bronze)), (rivets, c(Dye.bronzeDeep))]
        case .crown:
            let lean = CGAffineTransform(translationX: 0, y: -0.6).concatenating(CGAffineTransform(rotationAngle: -0.1)).concatenating(CGAffineTransform(translationX: 0, y: 0.6))
            var back = Path(), gold = poly([P(-3.9, -0.7), P(3.9, -0.7), P(3.9, 0.9), P(2.0, 1.25), P(0, 1.35), P(-2.0, 1.25), P(-3.9, 0.9)])
            for x in [-1.3, 1.3] as [CGFloat] {
                back.addPath(poly([P(x - 1.1, -0.5), P(x, -3.2), P(x + 1.1, -0.5)]))
                back.addPath(oval(x, -3.35, 0.45, 0.45))
            }
            for (x, h) in [(-2.6, 2.7), (0, 3.6), (2.6, 2.7)] as [(CGFloat, CGFloat)] {
                gold.addPath(poly([P(x - 1.3, -0.5), P(x, -0.5 - h), P(x + 1.3, -0.5)]))
                gold.addPath(oval(x, -0.7 - h, 0.55, 0.55))
            }
            var pinks = oval(-2.3, 0.3, 0.55, 0.48)
            pinks.addPath(oval(2.3, 0.3, 0.55, 0.48))
            var shine = oval(-2.75, -3.55, 0.2, 0.2)
            shine.addPath(poly([P(-3.55, -0.4), P(-2.95, -0.4), P(-3.05, 0.75), P(-3.55, 0.7)]))
            shine.addPath(poly([P(-0.35, -1.0), P(0, -3.3), P(0.15, -3.0), P(-0.05, -1.0)]))
            return [(back.applying(lean), c(Dye.goldDeep)), (gold.applying(lean), c(Dye.gold)), (oval(0, 0.32, 0.8, 0.62).applying(lean), c(Dye.turquoise)), (pinks.applying(lean), c(Dye.pink)), (shine.applying(lean), c(Dye.white, 0.6))]
        case .bowler:
            let lean = CGAffineTransform(translationX: 0, y: -1.0).concatenating(CGAffineTransform(rotationAngle: -0.07)).concatenating(CGAffineTransform(translationX: 0, y: 1.0))
            let dome = blob([P(-4.1, 1.0), P(-4.4, -1.0), P(-3.6, -3.3), P(-1.6, -4.7), P(1.6, -4.7), P(3.6, -3.3), P(4.4, -1.0), P(4.1, 1.0), P(0, 1.1)])
            var ink = dome
            ink.addPath(blob([P(-6.7, -0.4), P(-4.6, 0.4), P(0, 0.8), P(4.6, 0.4), P(6.7, -0.4), P(6.3, 0.7), P(3.6, 1.7), P(0, 1.9), P(-3.6, 1.7), P(-6.3, 0.7)]))
            let band = poly([P(-4.6, -0.7), P(4.6, -0.7), P(4.6, 0.9), P(-4.6, 0.9)]).intersection(dome)
            let shine = blob([P(-3.4, -1.4), P(-2.6, -3.0), P(-1.2, -3.9), P(-0.9, -3.5), P(-2.1, -2.6), P(-2.7, -1.1)])
            return [(ink.applying(lean), c(Dye.ink)), (band.applying(lean), c(Dye.satin, nested: true)), (shine.applying(lean), c(Dye.white, 0.2))]
        case .quiff:
            let sway = (pose.air ? 0.7 : 0.25 * sin(s * 2)) * (1 - pose.sit)
            let hair = blob([P(-6.1, 3.4), P(-6.4, 1.0), P(-5.2, -1.0), P(-2.9, -2.0), P(-0.6, -3.5), P(1.8, -5.6 - sway * 0.3), P(4.4 + sway * 0.5, -6.9), P(6.6 + sway, -6.4), P(7.6 + sway, -4.6), P(5.9 + sway * 0.4, -4.1), P(5.0, -2.4), P(5.2, 0.2), P(4.4, 1.2), P(2.0, 1.0), P(-1.0, 0.9), P(-3.6, 1.6)], sharp: [8])
            var deep = ribbon(trace([P(-5.4, 0.6), P(-2.6, -0.8), P(0.2, -2.6), P(2.8, -4.6), P(5.2 + sway * 0.5, -5.8)]), { 0.5 - 0.3 * $0 })
            deep.addPath(ribbon(trace([P(-3.4, 1.0), P(-0.6, -0.4), P(2.0, -2.2), P(4.4, -3.8), P(6.6 + sway * 0.6, -4.6)]), { 0.5 - 0.3 * $0 }))
            deep.addPath(ribbon(trace([P(0.4, 0.9), P(2.8, -0.2), P(5.0, -1.8)]), { 0.45 - 0.2 * $0 }))
            let shine = ribbon(trace([P(-2.2, -1.9), P(0.4, -3.6), P(2.6, -5.5), P(4.8 + sway * 0.5, -6.2)]), { 0.2 + 0.7 * sin(.pi * $0) })
            return [(hair, c(Dye.chestnut)), (deep, c(Dye.chestnutDeep)), (shine, c(Dye.white, 0.25))]
        case .curls:
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(-5.2, 1.5, 1.3), (-5.5, -0.7, 1.5), (-3.9, -2.3, 1.7), (-1.1, -3.2, 1.8), (1.8, -2.9, 1.7), (4.2, -1.8, 1.6), (5.5, 0.1, 1.35), (-2.9, -0.3, 1.5), (0.4, -0.9, 1.6), (3.1, 0.1, 1.4)]
            var edge = Path(), fill = Path(), spirals = Path(), shine = Path()
            for (k, d) in spots.enumerated() {
                let bob = pose.air ? -0.25 : 0.2 * sin(2 * s + CGFloat(k) * 1.3) * walk
                let o = P(d.0, d.1 + bob), r = d.2
                edge.addPath(oval(o.x + 0.1, o.y + 0.15, r + 0.3, r + 0.3))
                fill.addPath(oval(o.x, o.y, r, r))
                let turn = CGFloat(k) * 1.9
                spirals.addPath(ribbon((0...10).map { j in let t = CGFloat(j) / 10, a = turn + t * 4.4, q = r * 0.66 * (1 - 0.65 * t); return P(o.x + q * cos(a), o.y + q * sin(a)) }, { _ in 0.34 }))
                shine.addPath(oval(o.x - r * 0.45, o.y - r * 0.5, r * 0.25, r * 0.18).turned(-0.6, P(o.x - r * 0.45, o.y - r * 0.5)))
            }
            return [(edge, c(Dye.chestnutDeep)), (fill, c(Dye.chestnut)), (spirals, c(Dye.chestnutDeep)), (shine, c(Dye.white, 0.3))]
        case .bun:
            let sway = (pose.air ? 0.4 : 0.15 * sin(s * 2)) * (1 - pose.sit)
            let cap = blob([P(-6.3, 3.6), P(-6.1, 2.0), P(-5.3, 0.4), P(-3.8, -0.6), P(-1.8, -1.1), P(0.4, -1.1), P(2.8, -0.9), P(4.6, -0.2), P(5.5, 0.9), P(5.5, 1.8), P(4.2, 1.3), P(2, 1.0), P(-0.5, 0.9), P(-3.0, 1.4), P(-4.6, 2.4), P(-5.3, 3.5)])
            let o = P(-0.8 - sway, -3.5)
            var knot = oval(o.x, o.y, 2.6, 2.5)
            knot.addPath(oval(o.x, o.y + 2.0, 1.6, 0.9))
            var deep = ribbon(trace([P(o.x - 1.9, o.y + 0.2), P(o.x - 1.2, o.y - 1.7), P(o.x + 0.4, o.y - 2.2), P(o.x + 1.8, o.y - 1.2)]), { _ in 0.35 })
            deep.addPath(ribbon(trace([P(o.x - 1.3, o.y + 1.0), P(o.x - 0.4, o.y - 0.5), P(o.x + 0.7, o.y - 1.2)]), { _ in 0.35 }))
            deep.addPath(ribbon(trace([P(o.x + 0.2, o.y + 1.4), P(o.x + 1.2, o.y + 0.2), P(o.x + 1.9, o.y - 0.5)]), { _ in 0.35 }))
            let band = oval(o.x, o.y + 2.0, 1.55, 0.55)
            let shine = oval(o.x - 0.9, o.y - 1.1, 0.7, 0.45).turned(-0.6, P(o.x - 0.9, o.y - 1.1))
            return [(cap, c(Dye.chestnut)), (knot, c(Dye.chestnut)), (deep, c(Dye.chestnutDeep)), (band, c(Dye.turquoise)), (oval(o.x - 0.3, o.y + 2.0, 0.6, 0.2), c(Dye.white, 0.35)), (shine, c(Dye.white, 0.28))]
        default:
            return []
        }
    }

    private func ear(_ base: CGPoint, _ angle: CGFloat, _ flop: CGFloat, _ length: CGFloat) -> (Path, Path) {
        let bend = P(base.x + sin(angle) * length * 0.6, base.y - cos(angle) * length * 0.6)
        let tip = P(bend.x + sin(angle + flop) * length * 0.4, bend.y - cos(angle + flop) * length * 0.4)
        let mid = P(base.x + sin(angle) * length * 0.3, base.y - cos(angle) * length * 0.3)
        let line = trace([base, mid, bend, tip], 5)
        var outer = ribbon(line, { 1.6 + 1.6 * sin(.pi * min(1, $0 * 1.12)) })
        outer.addPath(oval(tip.x, tip.y, 0.95, 0.95))
        return (outer, ribbon(line, { 0.6 + 1.0 * sin(.pi * $0) }, 0.16...0.88))
    }

    private var dome: Layers {
        let line = height / 2 - 0.9
        var details = Path(roundedRect: CGRect(x: -4.9, y: line - 0.35, width: 1.1, height: 0.7), cornerRadius: 0.3)
        details.addPath(Path(roundedRect: CGRect(x: 2.6, y: line - 0.35, width: 1.1, height: 0.7), cornerRadius: 0.3))
        return [(Path(roundedRect: CGRect(x: -7.5, y: line - 0.75, width: 15, height: 1.5), cornerRadius: 0.75), c(Dye.white)), (details, c(Dye.blue))]
    }

    private var glass: Layers {
        let r: CGFloat = 8.8, line = height / 2 - 0.9, rise = sqrt(r * r - 7.2 * 7.2), cy = line - rise, a0 = asin(rise / r)
        let arc = (0...28).map { k in let a = .pi - a0 + CGFloat(k) / 28 * (.pi + 2 * a0); return P(r * cos(a), cy + r * sin(a)) }
        let rim = ribbon(arc, { _ in 0.5 })
        let glint = (0...8).map { k in let a = .pi + 0.45 + CGFloat(k) / 8 * 0.75; return P((r - 1.3) * cos(a), cy + (r - 1.3) * sin(a)) }
        var shine = ribbon(glint, { 0.5 + 0.5 * sin(.pi * $0) })
        shine.addPath(oval(4.6, cy - 5.6, 0.45, 0.45))
        return [(poly(arc), c(Dye.glass, 0.16)), (rim, c(Dye.white, 0.55)), (shine, c(Dye.white, 0.8))]
    }

    private func face(_ item: PetItem) -> Layers {
        let e = eye, edge = half
        switch item {
        case .shades:
            let o = P(e.x + 0.15, e.y + 0.1 + 0.8 * abs(sin(pose.tilt)))
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(o.x + x, o.y + y) }
            var ink = blob([q(-2.1, -1.5), q(2.3, -1.5), q(2.45, -0.6), q(1.7, 1.25), q(0.2, 1.55), q(-1.5, 1.2), q(-2.2, -0.4)])
            ink.addPath(ribbon(trace([q(-2.3, -1.4), q(2.5, -1.4)]), { _ in 0.8 }))
            ink.addPath(ribbon(trace([q(-2.0, -1.1), P(-0.8, o.y - 0.8), P(-2.8, o.y - 0.4)]), { _ in 0.65 }))
            ink.addPath(ribbon(trace([q(2.3, -0.9), P(edge - 0.2, o.y - 0.9)]), { _ in 0.6 }))
            ink.addPath(blob([P(edge - 0.5, o.y - 1.4), P(edge + 0.5, o.y - 1.2), P(edge + 0.6, o.y + 0.2), P(edge + 0.1, o.y + 1.0), P(edge - 0.5, o.y + 0.8)]))
            var shine = poly([q(-1.4, -0.95), q(-0.5, -0.95), q(-1.5, 1.0), q(-2.0, 0.5)])
            shine.addPath(poly([q(0.1, -0.95), q(0.5, -0.95), q(-0.5, 1.2), q(-0.9, 1.2)]))
            return [(ink, c(Dye.ink)), (shine, c(Dye.white, 0.4))]
        case .round:
            let o = P(e.x + 0.1, e.y - 0.1)
            var rim = ring(o, 2.1, 1.5)
            rim.addPath(ribbon(trace([P(o.x - 2.0, o.y - 0.4), P(-0.6, o.y - 0.5), P(-2.6, o.y - 0.2)]), { _ in 0.6 }))
            rim.addPath(ribbon(trace([P(o.x + 2.0, o.y - 0.5), P(o.x + 2.6, o.y - 0.75), P(edge - 0.2, o.y - 0.6)]), { _ in 0.6 }))
            rim.addPath(ribbon(trace([P(edge - 0.2, o.y - 1.9), P(edge + 0.45, o.y - 1.1), P(edge + 0.55, o.y + 0.4), P(edge + 0.05, o.y + 1.6)]), { _ in 0.6 }))
            let glint = ribbon((0...6).map { k in let a = 3.5 + CGFloat(k) / 6 * 0.9; return P(o.x + 1.05 * cos(a), o.y + 1.05 * sin(a)) }, { _ in 0.4 })
            return [(oval(o.x, o.y, 1.5, 1.5), c(Dye.white, 0.2)), (rim, c(Dye.ink)), (glint, c(Dye.white, 0.8))]
        case .hearts:
            let o = P(e.x + 0.2, e.y)
            var frame = heart(o, 2.6)
            frame.addPath(heart(o, 1.95, hole: true))
            frame.addPath(ribbon(trace([P(o.x - 2.4, o.y - 0.9), P(-0.6, o.y - 0.8), P(-2.6, o.y - 0.4)]), { _ in 0.6 }))
            frame.addPath(ribbon(trace([P(o.x + 2.4, o.y - 0.9), P(edge - 0.2, o.y - 0.9)]), { _ in 0.6 }))
            frame.addPath(heart(P(edge + 0.1, o.y), 0.9).applying(CGAffineTransform(translationX: -(edge + 0.1), y: -o.y).concatenating(CGAffineTransform(scaleX: 0.55, y: 1.6)).concatenating(CGAffineTransform(translationX: edge + 0.1, y: o.y))))
            return [(heart(o, 1.95), c(Dye.pinkDeep, 0.55)), (frame, c(Dye.blush)), (oval(o.x - 0.9, o.y - 0.7, 0.35, 0.35), c(Dye.white, 0.8))]
        case .mask:
            let o = e
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(o.x + x, o.y + y) }
            var mask = blob([q(-3.7, -1.7), q(-1.6, -1.8), q(0.4, -2.1), q(2.3, -1.9), P(edge + 0.35, o.y - 1.25), P(edge + 0.45, o.y + 0.25), P(edge - 0.35, o.y + 0.95), q(1.9, 1.45), q(0.2, 1.75), q(-1.5, 1.4), q(-2.8, 0.3)], sharp: [0])
            mask.addPath(blob([q(-1.85, -0.15), q(-0.7, -1.45), q(0.8, -1.55), q(1.75, -0.4), q(1.3, 1.1), q(-0.3, 1.45)], sharp: [0], hole: true))
            let k = P(-edge + 0.1, o.y + 0.1)
            mask.addPath(ribbon(trace([q(-3.0, -0.75), P((k.x + o.x - 3.0) / 2, o.y - 0.3), k]), { _ in 0.75 }))
            mask.addPath(oval(k.x, k.y, 0.65, 0.65))
            let f = pose.air ? sin(pose.lift * 0.9) : sin(2 * CGFloat(pose.step)) * walk
            let droop: CGFloat = sealed ? 2.2 : pose.air ? -0.6 : 0.5
            mask.addPath(ribbon(trace([k, P(k.x - 1.7, k.y - 0.5 + 0.3 * f + droop * 0.4), P(k.x - (sealed ? 2.4 : 3.3), k.y - 0.6 + droop + 0.6 * f)]), { 1.15 - 0.4 * $0 }))
            mask.addPath(ribbon(trace([k, P(k.x - 1.5, k.y + 0.8 - 0.3 * f + droop * 0.4), P(k.x - (sealed ? 2.0 : 2.8), k.y + 1.8 + droop - 0.5 * f)]), { 1.15 - 0.4 * $0 }))
            let sheen = ribbon(trace([q(-2.6, -1.35), q(-0.6, -1.75), q(1.6, -1.6)]), { 0.2 + 0.4 * sin(.pi * $0) })
            return [(mask, c(Dye.midnight)), (sheen, c(Dye.white, 0.22))]
        case .monocle:
            let o = P(e.x - 0.2, e.y - 0.2)
            let drop = pose.air ? sin(pose.lift * 0.8) : sin(CGFloat(pose.step) + 0.5) * walk
            let end = pose.air ? P(o.x - 4.6 + 0.5 * drop, o.y + 4.2) : P(o.x - 3.8 + 0.5 * drop, o.y + 5.2)
            let chain = trace([P(o.x - 1.5, o.y + 1.5), P(o.x - 3.4, o.y + 2.0), end])
            let rim = ring(o, 2.0, 1.5)
            var gold = rim
            gold.addPath(ribbon(chain, { _ in 0.32 }))
            gold.addPath(oval(end.x, end.y, 0.42, 0.42))
            let crescent = rim.subtracting(rim.applying(CGAffineTransform(translationX: -0.45, y: -0.45)))
            let glint = ribbon((0...6).map { k in let a = 3.5 + CGFloat(k) / 6 * 0.9; return P(o.x + 1.1 * cos(a), o.y + 1.1 * sin(a)) }, { _ in 0.4 })
            return [(oval(o.x, o.y, 1.5, 1.5), c(Dye.glass, 0.22)), (gold, c(Dye.gold)), (crescent, c(Dye.goldDeep)), (glint, c(Dye.white, 0.8))]
        default:
            return []
        }
    }

    private var collar: Layers {
        let n = neck
        return [(ribbon(trace([P(-half + 0.2, n - 0.5), P(0, n + 0.25), P(3.6, n + 0.55), P(half - 0.2, n + 0.2)]), { _ in 0.75 }), c(Dye.violet)), (oval(3.6, n + 0.55, 0.62, 0.62), c(Dye.gold))]
    }

    private var cane: Layers {
        let w = half, s = CGFloat(pose.step), air = pose.air
        let bob = air ? 0 : 0.8 * (1 + 0.7 * pose.bounce) * abs(sin(s)) * (1 - pose.sit)
        let floor = height / 2 + 1.8 - 1.4 * pose.sit + (pose.outfit[.feet] == .skates ? 1.2 * (1 - pose.sit) : 0) + bob
        let grip = P(w + 1.0, waist + 1.4)
        let tip = air ? P(grip.x + 5.0 * sin(0.3 + 0.3 * sin(pose.lift * 0.8)), grip.y + 4.8) : P(grip.x + 0.8 + 1.4 * sin(s) * walk, floor - 0.9 * max(0, cos(s)) * walk)
        let shaft = trace([grip, P((grip.x + tip.x) / 2, (grip.y + tip.y) / 2), tip], 4)
        let crook = trace([grip, P(grip.x, grip.y - 1.0), P(grip.x + 0.5, grip.y - 1.8), P(grip.x + 1.3, grip.y - 2.0), P(grip.x + 2.0, grip.y - 1.4)])
        var gold = ribbon(crook, { 1.05 - 0.15 * $0 })
        gold.addPath(ribbon(Array(shaft.prefix(3)), { _ in 1.1 }))
        gold.addPath(oval(crook[crook.count - 1].x, crook[crook.count - 1].y, 0.55, 0.55))
        let ferrule = ribbon(Array(shaft.suffix(3)), { _ in 1.05 })
        let gleam = ribbon(Array(shaft.dropFirst(3)), { _ in 0.22 }).offsetBy(dx: -0.26, dy: 0)
        let glint = ribbon(trace([P(grip.x - 0.1, grip.y - 1.7), P(grip.x + 0.6, grip.y - 1.35)]), { _ in 0.28 })
        return [(ribbon(shaft, { _ in 0.95 }), c(Dye.satin)), (gleam, c(Dye.mist, 0.55)), (gold, c(Dye.gold)), (ferrule, c(Dye.steel)), (glint, c(Dye.white, 0.7))]
    }

    private func moustache(_ item: PetItem) -> Layers {
        let e = eye, s = CGFloat(pose.step), y = e.y + 2.5, x: CGFloat = 4.9
        let f = pose.air ? sin(pose.lift * 0.9) : sin(2 * s) * walk
        switch item {
        case .handlebar:
            var hair = oval(x, y + 0.35, 0.9, 0.6)
            var shine = Path()
            for d in [-1.0, 1.0] as [CGFloat] {
                let g = f * (d > 0 ? 1 : -0.8)
                let line = trace([P(x, y + 0.3), P(x + 0.6 * d, y + 0.5), P(x + 1.15 * d, y + 0.4), P(x + 1.5 * d, y + 0.25 + 0.12 * g), P(x + 1.4 * d, y - 0.1 + 0.12 * g), P(x + 1.1 * d, y - 0.15 + 0.12 * g)], 4)
                hair.addPath(ribbon(line, { 0.4 + 1.1 * pow(1 - $0, 1.3) }))
                shine.addPath(ribbon(Array(line.prefix(9)), { 0.25 * (1 - $0) }).offsetBy(dx: 0, dy: -0.25))
            }
            return [(hair, c(Dye.chestnutDeep)), (shine, c(Dye.white, 0.3))]
        case .chevron:
            let g = 0.2 * f
            let hair = blob([P(x - 1.5, y - 0.05), P(x - 0.75, y - 0.35), P(x, y - 0.4), P(x + 0.9, y - 0.35), P(x + 1.6, y + 0.05 + g), P(x + 1.3, y + 0.7 + g), P(x + 0.7, y + 0.85), P(x, y + 0.55), P(x - 0.7, y + 0.85), P(x - 1.3, y + 0.6 - g)], sharp: [3])
            var streaks = ribbon(trace([P(x - 1.2, y - 0.05), P(x - 0.3, y - 0.2), P(x + 0.6, y - 0.2), P(x + 1.3, y)]), { _ in 0.22 })
            streaks.addPath(ribbon(trace([P(x - 0.9, y + 0.3), P(x - 0.2, y + 0.15)]), { _ in 0.18 }))
            return [(hair, c(Dye.chestnutDeep)), (streaks, c(Dye.chestnut))]
        case .pencil:
            let y = y + 0.3
            var hair = Path()
            for d in [-1.0, 1.0] as [CGFloat] {
                let line = trace([P(x, y), P(x + 0.55 * d, y), P(x + 1.1 * d, y + 0.05 + 0.2 * f * d), P(x + 1.6 * d, y + 0.1 + 0.2 * f * d)], 4)
                hair.addPath(ribbon(line, { 1.1 - 0.3 * $0 }))
            }
            return [(hair, c(Dye.chestnutDeep))]
        default:
            return []
        }
    }

    private func scarf(_ item: PetItem) -> Layers {
        let n = neck + (item == .cravat && pose.outfit[.whiskers] != nil ? 0.9 : 0), w = half, s = CGFloat(pose.step)
        switch item {
        case .bowtie:
            let o = P(3.5, n + (pose.outfit[.whiskers] == nil ? 1.05 : 1.85))
            var ink = blob([P(o.x - 0.3, o.y - 0.4), P(o.x - 2.2, o.y - 1.25), P(o.x - 2.5, o.y), P(o.x - 2.2, o.y + 1.25), P(o.x - 0.3, o.y + 0.4)])
            ink.addPath(blob([P(o.x + 0.3, o.y - 0.4), P(o.x + 1.8, o.y - 1.15), P(o.x + 2.05, o.y), P(o.x + 1.8, o.y + 1.15), P(o.x + 0.3, o.y + 0.4)]))
            var folds = poly([P(o.x - 0.5, o.y - 0.35), P(o.x - 2.0, o.y - 1.0), P(o.x - 2.2, o.y - 0.2)])
            folds.addPath(poly([P(o.x + 0.5, o.y - 0.35), P(o.x + 1.6, o.y - 0.95), P(o.x + 1.8, o.y - 0.2)]))
            return [(ink, c(Dye.ink)), (folds, c(Dye.white, 0.16)), (Path(roundedRect: CGRect(x: o.x - 0.55, y: o.y - 0.65, width: 1.1, height: 1.3), cornerRadius: 0.45), c(Dye.satin))]
        case .scarf:
            let sway = sin(s + 0.8) * walk
            let tail: [CGPoint] = sealed ? [P(-w + 0.6, n + 0.9), P(-w - 0.5, n + 2.4), P(-w - 0.7, n + 4.0)]
                : pose.air ? [P(-w + 0.6, n + 0.6), P(-w - 1.6, n - 0.1 + 0.4 * sin(pose.lift * 0.8)), P(-w - 3.8, n - 0.5 - 0.5 * sin(pose.lift * 0.8))]
                : [P(-w + 0.6, n + 0.9), P(-w - 1.3 + 0.3 * sway, n + 2.0 + 0.4 * sway), P(-w - 3.0 + 0.5 * sway, n + 3.3 - 0.6 * sway)]
            let wrap = trace([P(-w - 0.3, n + 0.25), P(0, n + 0.6), P(w + 0.3, n + 0.3)], 8)
            let end = trace([P(2.6, n + 0.9), P(2.8 + 0.15 * sway, n + 2.6), P(3.0 + 0.3 * sway, n + 4.3)], 6), back = trace(tail, 6)
            var teal = ribbon(wrap, { _ in 2.1 })
            teal.addPath(oval(-w - 0.3, n + 0.25, 1.05, 1.05))
            teal.addPath(oval(w + 0.3, n + 0.3, 1.05, 1.05))
            teal.addPath(ribbon(end, { _ in 1.9 }))
            teal.addPath(ribbon(back, { _ in 1.85 }))
            var cream = Path()
            for k in 0..<5 { cream.addPath(ribbon(wrap, { _ in 2.1 }, CGFloat(k) * 0.2 + 0.06...CGFloat(k) * 0.2 + 0.13)) }
            for t in [0.3, 0.62] as [CGFloat] {
                cream.addPath(ribbon(end, { _ in 1.9 }, t...t + 0.14))
                cream.addPath(ribbon(back, { _ in 1.85 }, t...t + 0.14))
            }
            var fringe = Path()
            for line in [end, back] {
                let a = line[line.count - 2], b = line[line.count - 1], d = hypot(b.x - a.x, b.y - a.y)
                let u = P((b.x - a.x) / d, (b.y - a.y) / d)
                for k in [-0.6, 0, 0.6] as [CGFloat] {
                    let p0 = P(b.x - u.y * k, b.y + u.x * k)
                    fringe.addPath(ribbon([p0, P(p0.x + u.x * 0.9, p0.y + u.y * 0.9)], { _ in 0.42 }))
                }
            }
            teal.addPath(fringe)
            let shadow = ribbon(trace([P(-w + 0.5, n + 1.7), P(0, n + 2.0), P(w - 0.5, n + 1.75)]), { _ in 0.9 })
            return [(shadow, c(Dye.shade, 0.14)), (teal, c(Dye.turquoise)), (cream, c(Dye.cream))]
        case .cravat:
            let flick = pose.air ? 0.6 * sin(pose.lift * 0.8) : 0.3 * sin(s + 0.8) * walk
            let left = blob([P(1.0, n + 0.1), P(2.5, n - 0.5), P(4.1, n - 0.2), P(4.2, n + 1.0), P(3.9, n + 3.4), P(2.7, n + 3.0), P(1.6, n + 1.4)], sharp: [5])
            let right = blob([P(3.9, n - 0.2), P(5.4, n - 0.6), P(6.4, n + 0.2), P(6.0, n + 1.5), P(5.6 + flick, n + 3.1), P(4.5 + flick, n + 3.6), P(4.0, n + 1.1)], sharp: [5])
            var trim = ribbon(trace([P(2.8, n + 3.1), P(3.9, n + 3.45)]), { _ in 0.38 })
            trim.addPath(ribbon(trace([P(4.6 + flick, n + 3.4), P(5.7 + flick, n + 3.0)]), { _ in 0.38 }))
            let knot = oval(4.0, n + 0.55, 1.05, 0.85)
            let pin = P(4.0, n + 0.6)
            return [(left, c(Dye.lavender)), (right, c(Dye.lavender)), (trim, c(Dye.cream)), (knot, c(Dye.lavenderDeep)), (oval(2.7, n + 0.2, 0.9, 0.4), c(Dye.white, 0.4)), (oval(5.2, n + 0.1, 0.8, 0.35), c(Dye.white, 0.3)), (oval(pin.x, pin.y, 0.5, 0.5), c(Dye.goldDeep)), (oval(pin.x, pin.y, 0.36, 0.36), c(Dye.gold)), (oval(pin.x - 0.12, pin.y - 0.12, 0.1, 0.1), c(Dye.white, 0.85))]
        case .bandana:
            let f = pose.air ? sin(pose.lift * 0.9) : sin(2 * s) * walk
            var deep = ribbon(trace([P(-w + 0.1, n + 0.25), P(0, n + 0.55), P(w - 0.1, n + 0.3)]), { _ in 1.1 })
            deep.addPath(oval(-w + 0.1, n + 0.25, 0.55, 0.55))
            deep.addPath(oval(w - 0.1, n + 0.3, 0.55, 0.55))
            let k = P(-w + 0.2, n + 0.4)
            deep.addPath(oval(k.x, k.y, 0.8, 0.75))
            if !sealed {
                deep.addPath(ribbon(trace([k, P(k.x - 1.2, k.y - 0.5 + 0.2 * f), P(k.x - 2.2, k.y - 0.9 + 0.4 * f)]), { 0.9 - 0.3 * $0 }))
                deep.addPath(ribbon(trace([k, P(k.x - 1.1, k.y + 0.6 - 0.2 * f), P(k.x - 1.9, k.y + 1.4 - 0.3 * f)]), { 0.9 - 0.3 * $0 }))
            }
            let tri = blob([P(0.8, n + 0.2), P(w + 0.1, n + 0.1), P(w - 0.4, n + 1.6), P(3.9, n + 3.8), P(2.3, n + 2.4)], sharp: [3])
            var dots = Path()
            for d in [P(2.6, n + 1.1), P(4.3, n + 0.9), P(3.8, n + 2.3), P(5.3, n + 1.2), P(3.2, n + 1.7)] { dots.addPath(oval(d.x, d.y, 0.36, 0.36)) }
            return [(deep, c(Dye.indigoDeep)), (tri, c(Dye.indigo)), (dots, c(Dye.white))]
        default:
            return []
        }
    }

}
