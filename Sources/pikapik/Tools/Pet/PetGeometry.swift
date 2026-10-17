import SwiftUI

extension PetClothes {
    func torso(_ lift: CGFloat, to end: CGFloat) -> Path {
        let n = chest + lift, w = half
        let line = trace([P(-w - 1, n - 0.1), P(-2.5, n + 0.1), P(1.8, n + 0.5), P(3.8, n + 0.65), P(w + 1, n + 0.1)], 4)
        return Path(body.intersection(poly(line + [P(w + 1, end), P(-w - 1, end)])).cgPath)
    }

    func shirt(_ lift: CGFloat, hem: CGFloat, flare f: CGFloat) -> Path {
        let w = half, top = max(chest + 0.8, height / 2 - 4.5)
        var p = torso(lift, to: hem)
        guard f > 0 else { return p }
        p.addPath(poly([P(-w, top), P(-w + 2.5, hem), P(-w - f, hem)]))
        p.addPath(poly([P(w, top), P(w + f, hem), P(w - 2.5, hem)]))
        return p
    }

    var sleeves: Path {
        let n = chest, w = half
        var p = blob([P(-w + 0.4, n + 0.2), P(-w - 0.6, n + 0.6), P(-w - 0.85, n + 2.0), P(-w + 0.4, n + 2.3)])
        p.addPath(blob([P(w - 0.4, n + 0.3), P(w + 0.55, n + 0.65), P(w + 0.75, n + 1.95), P(w - 0.4, n + 2.15)]))
        return p
    }

    var cuffs: Path {
        let n = chest, w = half
        var p = ribbon(trace([P(-w - 0.6, n + 0.75), P(-w - 0.85, n + 2.05)]), { _ in 0.6 })
        p.addPath(ribbon(trace([P(w + 0.5, n + 0.8), P(w + 0.7, n + 1.95)]), { _ in 0.6 }))
        return p
    }

    func top(_ item: PetItem) -> Layers {
        let n = chest, w = half, b = height / 2
        let rib = ribbon(trace([P(-w + 0.3, n + 0.25), P(-2.5, n + 0.45), P(1.8, n + 0.85), P(3.8, n + 1.0), P(w - 0.3, n + 0.45)], 4), { _ in 0.7 })
        let free = pose.outfit[.legs] == nil
        switch item {
        case .tee:
            var tee = shirt(-0.4, hem: free ? b - 1.3 : waist + 0.5, flare: free ? 0.4 : 0)
            tee.addPath(sleeves)
            var deep = ribbon(trace([P(-1.2, n - 0.03), P(1.8, n + 0.46), P(3.8, n + 0.56), P(w - 0.25, n + 0.06)], 4), { 0.35 + 0.55 * sin(.pi * $0) })
            deep.addPath(cuffs)
            return [(tee, c(Dye.turquoise)), (deep, c(Dye.turquoiseDeep)), (heart(P(3.6, n + 2.4), 0.95), c(Dye.pink))]
        case .stripes:
            var white = shirt(-0.3, hem: free ? b - 1.6 : waist + 0.5, flare: free ? 0.4 : 0)
            white.addPath(sleeves)
            var bands = Path()
            for k in 0..<6 { bands.addRect(CGRect(x: -w - 2, y: n + 0.8 + CGFloat(k) * 1.45, width: 2 * w + 4, height: 0.72)) }
            return [(white, c(Dye.white)), (bands.intersection(white), c(Dye.navy, nested: true))]
        case .hero:
            let trunk = torso(0, to: b + 1)
            var suit = trunk
            suit.addPath(sleeves)
            suit.addPath(trousers)
            var gold = ring(P(3.5, n + 2.2), 1.45, 0.95)
            gold.addPath(oval(3.5, n + 2.45, 0.42, 0.32))
            for (dx, dy) in [(-0.42, -0.25), (0, -0.48), (0.42, -0.25)] as [(CGFloat, CGFloat)] { gold.addPath(oval(3.5 + dx, n + 2.2 + dy, 0.17, 0.17)) }
            gold.addPath(cuffs)
            gold.addPath(trunk.intersection(Path(CGRect(x: -w - 1, y: b - 2.3, width: 2 * w + 2, height: 0.85))))
            return [(suit, c(Dye.midnight)), (gold, c(Dye.gold)), (Path(roundedRect: CGRect(x: 3.1, y: b - 2.45, width: 1.4, height: 1.15), cornerRadius: 0.3), c(Dye.goldDeep))]
        case .suit:
            var white = torso(0, to: b + 1)
            white.addPath(sleeves)
            white.addPath(trousers)
            var blue = rib
            blue.addPath(Path(roundedRect: CGRect(x: 2.2, y: n + 1.5, width: 2.8, height: 1.7), cornerRadius: 0.45))
            blue.addPath(cuffs)
            var boots = Path()
            for p in paws where pose.sit < 0.5 && p.maxY - 0.95 > b - 0.3 { boots.addPath(Path(CGRect(x: p.minX - 0.1, y: p.maxY - 1.65, width: p.width + 0.2, height: 0.7))) }
            var lights = oval(2.9, n + 2.35, 0.32, 0.32)
            lights.addPath(oval(3.9, n + 2.35, 0.32, 0.32))
            return [(white, c(Dye.snow))] + (boots.isEmpty ? [] : [(boots, c(Dye.mist))]) + [(blue, c(Dye.blue)), (lights, c(Dye.white))]
        case .hoodie:
            let hem = b - 1.0
            var sage = shirt(-0.1, hem: hem, flare: 0.45)
            sage.addPath(sleeves)
            let roll = trace([P(-w + 0.15, n - 0.35), P(-2.5, n - 0.2), P(1.8, n + 0.25), P(3.8, n + 0.4), P(w - 0.2, n - 0.05)], 4)
            var deep = ribbon(roll.map { P($0.x, $0.y + 0.62) }, { 0.55 + 0.2 * (1 - $0) })
            deep.addPath(cuffs)
            deep.addPath(sage.intersection(Path(CGRect(x: -w - 1, y: hem - 0.75, width: 2 * w + 2, height: 0.75))))
            deep.addPath(blob([P(1.0, hem - 2.45), P(4.3, hem - 2.45), P(5.0, hem - 0.95), P(0.4, hem - 0.95)]))
            sage.addPath(ribbon(roll, { 1.5 - 0.5 * $0 }))
            var cords = ribbon([P(3.2, n + 0.8), P(3.1, n + 1.7)], { _ in 0.5 })
            cords.addPath(ribbon([P(4.6, n + 0.7), P(4.7, n + 1.55)], { _ in 0.5 }))
            cords.addPath(oval(3.1, n + 1.8, 0.32, 0.42))
            cords.addPath(oval(4.7, n + 1.65, 0.32, 0.42))
            return [(sage, c(Dye.sage)), (deep, c(Dye.sageDeep)), (cords, c(Dye.cream))]
        case .labcoat:
            var white = torso(0, to: b + 1)
            white.addPath(poly([P(-w + 0.6, b - 1.6), P(2.9, b - 1.6), P(3.1, b + 0.7), P(-w - 0.5, b + 0.7)]))
            white.addPath(sleeves)
            let v = poly([P(2.3, n + 0.3), P(5.3, n + 0.3), P(3.9, n + 2.4)])
            var mist = poly([P(2.1, n + 0.35), P(3.0, n + 0.35), P(3.8, n + 2.6), P(2.5, n + 1.6)])
            mist.addPath(poly([P(5.5, n + 0.35), P(4.7, n + 0.35), P(4.0, n + 2.6), P(5.3, n + 1.5)]))
            mist.addPath(ribbon([P(3.9, n + 2.2), P(3.9, b + 0.6)], { _ in 0.4 }))
            mist.addPath(ring(P(3.3, n + 3.0), 0.35, 0))
            mist.addPath(ring(P(3.3, n + 4.3), 0.35, 0))
            mist.addPath(ribbon([P(-0.4, n + 1.9), P(1.8, n + 1.9)], { _ in 0.5 }))
            var pen = Path(roundedRect: CGRect(x: 0.2, y: n + 0.7, width: 0.6, height: 1.6), cornerRadius: 0.3)
            pen.addPath(Path(CGRect(x: 0.65, y: n + 0.9, width: 0.35, height: 0.9)))
            return [(white, c(Dye.snow)), (v, c(Dye.snow)), (mist, c(Dye.mist)), (pen, c(Dye.blue))]
        case .tailcoat:
            let flap = (pose.air ? 0.5 + 0.1 * sin(pose.lift * 0.6) : 0.1 * sin(2 * CGFloat(pose.step)) * walk) - (pose.hang ? pose.tilt * 0.5 : 0)
            let hem = b + 0.4, pivot = P(-w + 1.0, waist - 0.6)
            var coat = torso(-0.1, to: b + 1).intersection(poly([P(-w - 1, n - 1), P(w + 1, n - 1), P(w + 1, waist - 0.2), P(1.6, waist + 0.1), P(-1.0, waist + 1.3), P(-3.2, b), P(-w - 1, b + 1)]))
            coat.addPath(sleeves)
            let tails = poly([P(-w - 0.4, waist - 0.9), P(-1.8, waist - 0.9), P(-2.4, hem), P(-3.3, hem - 1.3), P(-4.1, hem), P(-w - 1.1, hem - 0.3)]).turned(flap, pivot)
            let pleat = ribbon(trace([P(-3.3, hem - 1.3), P(-3.3, waist - 0.5)]), { _ in 0.35 }).turned(flap, pivot)
            let n = n + (pose.outfit[.whiskers] == nil ? 0 : 0.5)
            let shirt = poly([P(2.4, n + 0.25), P(5.8, n + 0.2), P(4.1, n + 3.7)])
            var lapel = poly([P(1.7, n + 0.3), P(2.7, n + 0.2), P(4.1, n + 3.7), P(3.4, n + 3.4), P(3.0, n + 2.0)])
            lapel.addPath(poly([P(5.6, n + 0.15), P(w - 0.1, n + 0.45), P(5.4, n + 1.9), P(4.9, n + 2.8), P(4.1, n + 3.7)]))
            var rose = oval(5.1, n + 1.3, 0.55, 0.55)
            rose.addPath(oval(4.8, n + 1.05, 0.3, 0.3))
            return [(coat, c(Dye.midnight)), (tails, c(Dye.midnight)), (pleat, c(Dye.shade, 0.35)), (shirt, c(Dye.white)), (lapel, c(Dye.indigo)), (rose, c(Dye.pink))]
        case .tweed:
            var jacket = torso(-0.1, to: b + 1)
            jacket.addPath(sleeves)
            var weave = Path(), check = Path()
            for r in 0..<6 {
                for k in 0..<12 {
                    let x = -w - 0.6 + CGFloat(k) * 1.15, y = n - 0.2 + CGFloat(r) * 1.0, up = k % 2 == 0
                    weave.addPath(poly([P(x, y + (up ? 0.8 : 0)), P(x + 0.4, y + (up ? 0.8 : 0)), P(x + 1.55, y + (up ? 0 : 0.8)), P(x + 1.15, y + (up ? 0 : 0.8))]))
                }
            }
            for k in 0..<5 { check.addRect(CGRect(x: -w - 0.2 + CGFloat(k) * 3.2, y: n - 1, width: 0.5, height: 12)) }
            for k in 0..<3 { check.addRect(CGRect(x: -w - 2, y: n + 0.8 + CGFloat(k) * 2.5, width: 2 * w + 4, height: 0.5)) }
            let shirt = poly([P(2.1, n + 0.4), P(w - 0.2, n + 0.3), P(3.9, n + 3.1)])
            var lapel = ribbon([P(1.9, n + 0.5), P(3.8, n + 3.2)], { 1.1 - 0.5 * $0 })
            lapel.addPath(ribbon([P(w - 0.3, n + 1.0), P(4.0, n + 3.2)], { 0.9 - 0.4 * $0 }))
            var buttons = oval(4.0, n + 3.9, 0.32, 0.32)
            buttons.addPath(oval(4.0, n + 4.9, 0.32, 0.32))
            var patch = oval(w + 0.15, n + 1.3, 0.42, 0.58)
            patch.addPath(oval(-w - 0.1, n + 1.3, 0.42, 0.58))
            let welt = ribbon([P(0.2, n + 1.7), P(1.9, n + 1.5)], { _ in 0.35 })
            let square = poly([P(0.5, n + 1.6), P(0.6, n + 0.7), P(1.0, n + 1.1), P(1.4, n + 0.6), P(1.7, n + 1.5)])
            return [(jacket, c(Dye.oat)), (weave.intersection(jacket), c(Dye.tan, 0.9, nested: true)), (check.intersection(jacket), c(Dye.chestnut, 0.85, nested: true)), (shirt, c(Dye.cream)), (lapel, c(Dye.tanDeep)), (patch, c(Dye.brown)), (welt, c(Dye.brown)), (square, c(Dye.pink)), (buttons, c(Dye.brown))]
        case .waistcoat:
            let vest = torso(0, to: b + 0.4)
            let shirt = poly([P(2.2, n + 0.4), P(w - 0.2, n + 0.3), P(3.9, n + 2.4)])
            var trim = ribbon([P(2.0, n + 0.45), P(3.9, n + 2.5)], { 0.6 - 0.2 * $0 })
            trim.addPath(ribbon([P(w - 0.3, n + 0.95), P(4.0, n + 2.5)], { 0.55 - 0.2 * $0 }))
            trim.addPath(ribbon([P(-0.4, n + 2.6), P(1.4, n + 2.5)], { _ in 0.35 }))
            var buttons = Path()
            for k in 0..<3 { buttons.addPath(oval(4.0, n + 2.9 + CGFloat(k) * 1.1, 0.3, 0.3)) }
            let watch = P(2.0, n + 2.3)
            var gold = ribbon(trace([P(4.0, n + 1.5), P(3.6, n + 2.2), P(2.8, n + 2.0), P(2.0, n + 1.1)]), { _ in 0.26 })
            gold.addPath(ring(watch, 0.9, 0.62))
            gold.addPath(oval(watch.x, watch.y - 1.05, 0.25, 0.3))
            return [(vest, c(Dye.pine)), (shirt, c(Dye.cream)), (trim, c(Dye.pineDeep)), (buttons, c(Dye.gold)), (oval(watch.x, watch.y, 0.65, 0.65), c(Dye.ivory)), (gold, c(Dye.gold)), (oval(watch.x - 0.18, watch.y - 0.18, 0.12, 0.12), c(Dye.white, 0.8))]
        case .tux:
            var ink = torso(-0.1, to: b + 1)
            ink.addPath(blob([P(-w + 0.3, waist - 1.6), P(-w + 2.6, waist + 0.2), P(-w + 2.0, b + 0.7), P(-w + 0.4, b + 1.0), P(-w - 0.5, waist + 0.3)]))
            let white = poly([P(1.3, n + 0.45), P(w - 0.15, n + 0.25), P(w - 0.45, n + 1.5), P(3.85, b - 0.4)])
            var satin = ribbon([P(1.25, n + 0.45), P(3.7, b - 0.5)], { 1.0 - 0.5 * $0 })
            satin.addPath(ribbon([P(w - 0.35, n + 1.3), P(4.05, b - 0.5)], { 0.8 - 0.35 * $0 }))
            var studs = oval(3.95, n + 2.0, 0.27, 0.27)
            studs.addPath(oval(3.95, n + 2.9, 0.27, 0.27))
            let rim = ink.subtracting(ink.applying(CGAffineTransform(translationX: 0.55, y: -0.45)))
            return [(ink, c(Dye.ink)), (rim, c(Dye.satin)), (white, c(Dye.white)), (satin, c(Dye.satin)), (studs, c(Dye.ink))]
        default:
            return []
        }
    }

    var trousers: Path {
        var legs = Path()
        guard pose.sit < 0.5 else { return legs }
        let b = height / 2
        for p in paws where p.maxY - 0.95 > b - 0.9 {
            legs.addPath(Path(roundedRect: CGRect(x: p.minX - 0.1, y: b - 1.6, width: p.width + 0.2, height: p.maxY - 0.95 - (b - 1.6)), cornerRadius: 0.5))
        }
        return legs
    }

    func legs(_ item: PetItem) -> Layers {
        let t = waist, w = half, b = height / 2
        let pants = body.intersection(Path(CGRect(x: -w - 1, y: t, width: 2 * w + 2, height: b - t + 1)))
        switch item {
        case .jeans:
            var denim = pants
            denim.addPath(trousers)
            var deep = pants.intersection(Path(CGRect(x: -w - 1, y: t, width: 2 * w + 2, height: 0.8)))
            for p in paws where pose.sit < 0.5 && p.maxY - 0.95 > b - 0.3 { deep.addPath(Path(CGRect(x: p.minX - 0.1, y: p.maxY - 1.55, width: p.width + 0.2, height: 0.6))) }
            deep.addPath(blob([P(-4.7, t + 1.25), P(-2.2, t + 1.25), P(-2.3, t + 2.5), P(-3.45, t + 3.0), P(-4.6, t + 2.5)], sharp: [0, 1]))
            let seam = ribbon(trace([P(2.0, t + 0.8), P(2.9, t + 1.7), P(4.1, t + 2.2)]), { _ in 0.6 })
            return [(denim, c(Dye.denim)), (deep, c(Dye.denimDeep)), (seam, c(Dye.denimLight))]
        case .overalls:
            let n = neck
            var denim = pants
            denim.addPath(trousers)
            denim.addPath(Path(roundedRect: CGRect(x: 1.0, y: n + 0.3, width: 4.6, height: t - n + 0.4), cornerRadius: 0.5))
            denim.addPath(ribbon(trace([P(1.5, n + 0.6), P(-1.6, n + 0.1), P(-w + 0.2, n - 0.35)]), { _ in 0.95 }))
            denim.addPath(ribbon(trace([P(5.1, n + 0.6), P(w - 0.1, n - 0.2)]), { _ in 0.95 }))
            let deep = Path(roundedRect: CGRect(x: 2.0, y: n + 1.4, width: 2.6, height: 1.6), cornerRadius: 0.4)
            var seams = ribbon([P(1.5, n + 1.1), P(1.5, t + 0.2)], { _ in 0.6 })
            seams.addPath(ribbon([P(5.1, n + 1.1), P(5.1, t + 0.2)], { _ in 0.6 }))
            var buttons = oval(1.6, n + 0.75, 0.45, 0.45)
            buttons.addPath(oval(5.05, n + 0.7, 0.45, 0.45))
            return [(denim, c(Dye.denim)), (deep, c(Dye.denimDeep)), (seams, c(Dye.denimLight)), (buttons, c(Dye.silver))]
        case .tutu:
            var low = Path(), high = Path(), dots = Path()
            for k in 0..<11 { let x = -7.2 + CGFloat(k) * 1.44; low.addPath(oval(x, t + 0.7 + 0.02 * x * x, 1.15, 1.15)) }
            for k in 0..<9 { let x = -6.4 + CGFloat(k) * 1.6; high.addPath(oval(x, t + 0.05 + 0.02 * x * x, 1.05, 1.05)) }
            for (x, y) in [(-4.8, 0.3), (-1.6, 0.1), (1.8, 0.4), (4.6, 0.2), (-3.0, 1.6), (3.2, 1.7)] as [(CGFloat, CGFloat)] { dots.addPath(oval(x, t + y, 0.22, 0.22)) }
            let band = ribbon(trace([P(-w + 0.4, t - 0.75), P(0, t - 0.6), P(w - 0.4, t - 0.75)]), { _ in 0.9 })
            return [(low, c(Dye.pinkDeep)), (high, c(Dye.pink)), (band, c(Dye.lavenderDeep)), (dots, c(Dye.white, 0.85, nested: true))]
        default:
            return []
        }
    }

    func shoes(_ item: PetItem) -> Layers {
        var a = Path(), b = Path(), d = Path(), e = Path(), f = Path()
        let turn = CGFloat(pose.step) * 2.2
        for p in paws {
            switch item {
            case .sneakers:
                a.addPath(Path(roundedRect: CGRect(x: p.minX - 0.2, y: p.minY - 0.15, width: p.width + 0.6, height: p.height + 0.15), cornerRadius: 1.3))
                b.addPath(Path(roundedRect: CGRect(x: p.minX - 0.25, y: p.maxY - 0.8, width: p.width + 0.75, height: 0.85), cornerRadius: 0.42))
                b.addPath(Path(roundedRect: CGRect(x: p.minX + 1.9, y: p.minY + 0.15, width: 0.5, height: 0.9), cornerRadius: 0.25))
                b.addPath(Path(roundedRect: CGRect(x: p.minX + 2.8, y: p.minY + 0.35, width: 0.5, height: 0.9), cornerRadius: 0.25))
            case .boots:
                a.addPath(blob([P(p.minX - 0.1, p.minY - 1.7), P(p.minX + 2.7, p.minY - 1.7), P(p.minX + 2.8, p.minY - 0.2), P(p.maxX + 0.35, p.minY + 0.7), P(p.maxX + 0.35, p.maxY), P(p.minX - 0.2, p.maxY)], sharp: [0, 1, 4, 5]))
                b.addPath(Path(roundedRect: CGRect(x: p.minX - 0.25, y: p.maxY - 0.6, width: p.width + 0.65, height: 0.65), cornerRadius: 0.3))
                b.addPath(Path(CGRect(x: p.minX - 0.1, y: p.minY - 1.7, width: 2.8, height: 0.45)))
                d.addPath(oval(p.maxX - 0.4, p.minY + 1.1, 0.55, 0.3))
                d.addPath(Path(roundedRect: CGRect(x: p.minX + 0.4, y: p.minY - 1.0, width: 0.45, height: 1.7), cornerRadius: 0.22))
            case .spats:
                a.addPath(Path(roundedRect: CGRect(x: p.minX - 0.2, y: p.minY - 0.15, width: p.width + 0.6, height: p.height + 0.15), cornerRadius: 1.3))
                d.addPath(Path(roundedRect: CGRect(x: p.minX - 0.25, y: p.maxY - 0.6, width: p.width + 0.65, height: 0.65), cornerRadius: 0.3))
                b.addPath(Path(roundedRect: CGRect(x: p.minX - 0.1, y: p.minY - 1.3, width: p.width * 0.68, height: 1.3 + p.height * 0.62), cornerRadius: 0.55))
                for k in 0..<3 { e.addPath(oval(p.minX + p.width * 0.68 - 0.5, p.minY - 0.7 + CGFloat(k) * 0.55, 0.15, 0.15)) }
                f.addPath(Path(roundedRect: CGRect(x: p.minX + 0.2, y: p.minY - 1.0, width: 0.4, height: 1.5), cornerRadius: 0.2))
            case .skates:
                for x in [p.minX + 0.9, p.maxX - 0.7] {
                    let o = P(x, p.maxY + 0.35)
                    a.addPath(oval(o.x, o.y, 0.85, 0.85))
                    for k in 0..<2 {
                        let ang = turn + CGFloat(k) * .pi / 2, u = P(cos(ang) * 0.6, sin(ang) * 0.6)
                        b.addPath(ribbon([P(o.x - u.x, o.y - u.y), P(o.x + u.x, o.y + u.y)], { _ in 0.4 }))
                    }
                    b.addPath(oval(o.x, o.y, 0.26, 0.26))
                }
                d.addPath(Path(roundedRect: CGRect(x: p.minX - 0.1, y: p.maxY - 0.3, width: p.width + 0.3, height: 0.55), cornerRadius: 0.27))
                e.addPath(Path(roundedRect: CGRect(x: p.minX - 0.15, y: p.minY - 1.0, width: p.width + 0.5, height: p.height + 0.75), cornerRadius: 1.2))
                f.addPath(oval(p.maxX + 0.3, p.maxY - 0.15, 0.5, 0.45))
                f.addPath(Path(roundedRect: CGRect(x: p.minX + 1.9, y: p.minY - 0.7, width: 0.5, height: 1.0), cornerRadius: 0.25))
            default:
                break
            }
        }
        switch item {
        case .sneakers: return [(a, c(Dye.snow)), (b, c(Dye.blue))]
        case .boots: return [(a, c(Dye.yellow)), (b, c(Dye.yellowDeep)), (d, c(Dye.white, 0.55))]
        case .spats: return [(a, c(Dye.ink)), (d, c(Dye.satin)), (b, c(Dye.cream)), (e, c(Dye.ink)), (f, c(Dye.white, 0.6))]
        case .skates: return [(a, c(Dye.turquoise)), (b, c(Dye.white)), (d, c(Dye.steelDeep)), (e, c(Dye.snow)), (f, c(Dye.pink))]
        default: return []
        }
    }

    func inside(_ layers: Layers) -> Layers {
        let edge: CGFloat = 14.7
        let r = layers.reduce(CGRect.null) { $0.union($1.0.applying(place).boundingRect) }
        guard r.minX < -edge || r.maxX > edge else { return layers }
        let o = P(-half + 1.2, neck - 0.6).applying(place).x
        let k = min(r.maxX > edge ? (edge - o) / (r.maxX - o) : 1, r.minX < -edge ? (o + edge) / (o - r.minX) : 1)
        let squeeze = place.concatenating(CGAffineTransform(a: k, b: 0, c: 0, d: 1, tx: o * (1 - k), ty: 0)).concatenating(place.inverted())
        return layers.map { ($0.0.applying(squeeze), $0.1) }
    }

    func back(_ item: PetItem) -> Layers {
        let n = neck, w = half, s = CGFloat(pose.step)
        switch item {
        case .cape:
            let pivot = P(-w + 1.2, n - 0.6), hem = min(height / 2 + 1.4, ground - 0.3)
            let f = 0.35 * sin(2 * s) * walk
            let flap = (pose.air ? 0.85 + 0.12 * sin(pose.lift * 0.6) : 0.1 + 0.05 * sin(2 * s) * walk) - (pose.hang ? pose.tilt * 0.6 : 0)
            let cape = blob([P(-1.5, n - 0.8), P(-w + 0.4, n - 0.95), P(-w - 1.1, n + 0.5), P(-w - 2.3 + f, hem - 1.5), P(-w - 2.9 + f, hem), P(-w - 0.8 - f, hem + 0.25), P(-1.0, hem - 0.2)])
            var folds = ribbon(trace([P(-w - 0.3, n + 1.6), P(-w - 1.2 + f, hem - 1.0), P(-w - 1.6 + f, hem - 0.1)]), { 0.3 + 0.5 * $0 })
            folds.addPath(ribbon(trace([P(-w + 0.4, n + 2.4), P(-w - 0.1 - f, hem - 0.4), P(-w - 0.1 - f, hem + 0.1)]), { 0.2 + 0.5 * $0 }))
            return [(cape.turned(flap, pivot), c(Dye.violet)), (folds.turned(flap, pivot), c(Dye.violetDeep))]
        case .balloon:
            let tie = P(-w + 1.0, n + 0.6).applying(place)
            let lag = pose.air ? min(1, 0.5 + 5 * abs(pose.squash)) : 0
            let sway = 0.9 * sin(s * 0.5 + 0.8) * (1 - lag)
            let knot = P(min(max(tie.x - pose.facing * (3.0 + 1.5 * lag) + sway, -11.8), 11.8), tie.y - 12.0 + 3.0 * lag)
            let o = P(knot.x, knot.y - 3.3)
            let lean = CGAffineTransform(translationX: -knot.x, y: -knot.y).concatenating(CGAffineTransform(rotationAngle: sway * 0.08)).concatenating(CGAffineTransform(translationX: knot.x, y: knot.y))
            var ball = blob([P(o.x, o.y - 3.4), P(o.x + 2.6, o.y - 2.2), P(o.x + 2.8, o.y + 0.4), P(o.x + 1.4, o.y + 2.7), P(o.x, o.y + 3.3), P(o.x - 1.4, o.y + 2.7), P(o.x - 2.8, o.y + 0.4), P(o.x - 2.6, o.y - 2.2)])
            ball.addPath(poly([P(knot.x - 0.55, knot.y + 0.45), P(knot.x + 0.55, knot.y + 0.45), P(knot.x, knot.y - 0.3)]))
            let mid = P((tie.x + knot.x) / 2 + 1.2 * (1 - lag) + 1.8 * lag * pose.facing, (tie.y + knot.y) / 2)
            let string = ribbon(trace([tie, mid, P(knot.x, knot.y + 0.4)], 8), { _ in 0.45 })
            let shine = oval(o.x - 1.2, o.y - 1.5, 0.6, 1.0).turned(0.5, P(o.x - 1.2, o.y - 1.5))
            let back = place.inverted()
            return [(string.applying(back), c(Dye.string)), (ball.applying(lean).applying(back), c(Dye.turquoise)), (shine.applying(lean).applying(back), c(Dye.white, 0.55))]
        case .wings:
            let root = P(-w + 2.2, n - 1.4)
            let flap = (pose.air ? 0.3 * sin(pose.lift * 1.1) : 0.1 * sin(2 * s) * walk) - (pose.hang ? 0.2 : 0)
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(root.x + x, root.y + y) }
            let upper = [q(0, 0), q(-3.0, -4.6), q(-6.2, -6.6), q(-7.6, -5.6), q(-6.6, -2.4), q(-2.0, 0.2)]
            let lower = [q(-0.4, 0.6), q(-4.6, 1.0), q(-6.4, 2.8), q(-5.2, 4.2), q(-2.0, 2.8)]
            var pair = blob(upper)
            pair.addPath(blob(lower))
            var rims = Path()
            for wing in [upper, lower] {
                rims.addPath(blob(wing))
                let cx = wing.reduce(0) { $0 + $1.x } / CGFloat(wing.count), cy = wing.reduce(0) { $0 + $1.y } / CGFloat(wing.count)
                rims.addPath(blob(wing.map { P(cx + ($0.x - cx) * 0.8, cy + ($0.y - cy) * 0.8) }, hole: true))
            }
            let far = CGAffineTransform(translationX: 0.9, y: -0.7)
            return [(pair.turned(flap - 0.3, root).applying(far), c(Dye.lavender, 0.38)), (pair.turned(flap, root), c(Dye.glass, 0.6)), (rims.turned(flap, root), c(Dye.lavender, 0.85))]
        case .umbrella:
            let up = pose.air ? 1.1 + 0.5 * sin(pose.lift * 0.8) : 0
            let handle = P(-w - 0.6, waist + 0.1), top = P(-1.6, -height / 2 - (pose.outfit[.head] == nil ? 4.1 : 6.0) - up)
            let len = hypot(top.x - handle.x, top.y - handle.y)
            let u = P((top.x - handle.x) / len, (top.y - handle.y) / len)
            let at = CGAffineTransform(a: -u.y, b: u.x, c: u.x, d: u.y, tx: top.x, ty: top.y)
            let sway = 0.05 * sin(2 * s) * walk - (pose.air ? 0.1 : 0) - (pose.hang ? pose.tilt * 0.6 : 0)
            func rib(_ x: CGFloat, _ from: CGFloat, _ to: CGFloat) -> [CGPoint] {
                (0...6).map { k in let a = from + (to - from) * CGFloat(k) / 6; return P(x * cos(a), 4.4 * sin(a)) }
            }
            var even = Path(), odd = Path()
            for k in 0..<5 {
                let x0 = -7.2 + 2.88 * CGFloat(k), x1 = x0 + 2.88
                let scallop = (0...4).map { j in let t = CGFloat(j) / 4; return P(x1 + (x0 - x1) * t, 0.6 * sin(.pi * t)) }
                let panel = poly(rib(x0, .pi / 2, 0) + scallop.reversed() + rib(x1, 0, .pi / 2))
                if k % 2 == 0 { even.addPath(panel) } else { odd.addPath(panel) }
            }
            let wood = ribbon(trace([P(0, 0.5), P(0, -len / 2), P(0, -len)]), { _ in 0.6 })
            var crook = ribbon(trace([P(0, -len), P(0, -len - 1.4), P(-0.4, -len - 2.3), P(-1.3, -len - 2.6), P(-2.0, -len - 2.0)]), { _ in 0.95 })
            crook.addPath(oval(-2.0, -len - 2.0, 0.48, 0.48))
            var gold = ribbon([P(0, 4.0), P(0, 5.5)], { 0.5 - 0.3 * $0 })
            gold.addPath(oval(0, 0.4, 0.5, 0.5))
            gold.addPath(ribbon([P(0, -len - 0.1), P(0, -len - 0.8)], { _ in 1.15 }))
            let shine = ribbon(trace([P(-5.6, 1.6), P(-4.4, 2.9), P(-2.8, 3.7)]), { _ in 0.4 })
            func fit(_ path: Path) -> Path { path.applying(at).turned(sway, handle) }
            return [(fit(wood), c(Dye.chestnutDeep)), (fit(crook), c(Dye.chestnut)), (fit(odd), c(Dye.cream)), (fit(even), c(Dye.indigo)), (fit(gold), c(Dye.gold)), (fit(shine), c(Dye.white, 0.3))]
        case .angel:
            let root = P(-w + 2.4, n - 1.4)
            let flap = (pose.air ? 0.25 * sin(pose.lift * 1.1) : 0.08 * sin(2 * s) * walk) - (pose.hang ? 0.15 : 0)
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(root.x + x, root.y + y) }
            var primaries = Path()
            for (from, to) in [(q(-3.0, -2.6), q(-8.5, -4.3)), (q(-2.6, -1.6), q(-8.0, -2.2)), (q(-2.2, -0.8), q(-6.9, -0.3)), (q(-1.6, -0.2), q(-5.3, 1.2)), (q(-1.0, 0.2), q(-3.3, 1.9))] {
                primaries.addPath(ribbon([from, to], { 1.6 - 0.2 * $0 }))
                primaries.addPath(oval(to.x, to.y, 0.72, 0.72))
            }
            var coverts = blob([q(0.2, 0.2), q(-0.8, -3.8), q(-3.5, -6.2), q(-6.8, -6.4), q(-7.9, -4.9), q(-5.9, -3.2), q(-3.5, -1.4), q(-1.2, 0.6)])
            for (x, y) in [(-7.0, -4.5), (-5.6, -3.3), (-4.2, -2.2), (-2.8, -1.0)] as [(CGFloat, CGFloat)] { coverts.addPath(oval(root.x + x, root.y + y, 0.9, 0.9)) }
            var wing = primaries
            wing.addPath(coverts)
            let far = CGAffineTransform(translationX: -root.x, y: -root.y).concatenating(CGAffineTransform(scaleX: 0.85, y: 0.85)).concatenating(CGAffineTransform(translationX: root.x + 1.2, y: root.y - 1.0))
            return [(wing.turned(flap - 0.25, root).applying(far), c(Dye.mist)), (primaries.turned(flap, root), c(Dye.feather)), (coverts.turned(flap, root), c(Dye.snow))]
        default:
            return []
        }
    }

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    func area(_ p: [CGPoint]) -> CGFloat {
    var a: CGFloat = 0
    for i in p.indices { let q = p[(i + 1) % p.count]; a += p[i].x * q.y - q.x * p[i].y }
    return a
}

    func poly(_ p: [CGPoint], hole: Bool = false) -> Path {
    var path = Path()
    path.addLines((area(p) > 0) != hole ? p : p.reversed())
    path.closeSubpath()
    return path
}

    func blob(_ points: [CGPoint], sharp: Set<Int> = [], hole: Bool = false) -> Path {
    let flip = (area(points) > 0) == hole, n = points.count
    let p = flip ? Array(points.reversed()) : points
    let corner = flip ? Set(sharp.map { n - 1 - $0 }) : sharp
    var path = Path()
    path.move(to: p[0])
    for i in 0..<n {
        let a = p[(i + n - 1) % n], b = p[i], c = p[(i + 1) % n], d = p[(i + 2) % n]
        let c1 = corner.contains(i) ? b : CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6)
        let c2 = corner.contains((i + 1) % n) ? c : CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6)
        path.addCurve(to: c, control1: c1, control2: c2)
    }
    path.closeSubpath()
    return path
}

    func trace(_ p: [CGPoint], _ n: Int = 6) -> [CGPoint] {
    var out = [p[0]]
    for i in 0..<(p.count - 1) {
        let a = p[max(i - 1, 0)], b = p[i], c = p[i + 1], d = p[min(i + 2, p.count - 1)]
        for k in 1...n {
            let t = CGFloat(k) / CGFloat(n), t2 = t * t, t3 = t2 * t
            func f(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
            }
            out.append(CGPoint(x: f(a.x, b.x, c.x, d.x), y: f(a.y, b.y, c.y, d.y)))
        }
    }
    return out
}

    func ribbon(_ c: [CGPoint], _ w: (CGFloat) -> CGFloat, _ range: ClosedRange<CGFloat> = 0...1) -> Path {
    let m = c.count - 1
    let lo = Int((range.lowerBound * CGFloat(m)).rounded()), hi = max(lo + 1, Int((range.upperBound * CGFloat(m)).rounded()))
    var l: [CGPoint] = [], r: [CGPoint] = []
    for i in lo...min(hi, m) {
        let a = c[max(i - 1, 0)], b = c[min(i + 1, m)]
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.0001), h = w(CGFloat(i) / CGFloat(m)) / 2
        l.append(CGPoint(x: c[i].x - dy / len * h, y: c[i].y + dx / len * h))
        r.append(CGPoint(x: c[i].x + dy / len * h, y: c[i].y - dx / len * h))
    }
    return poly(l + r.reversed())
}

    func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
}

    func circle(_ o: CGPoint, _ r: CGFloat, hole: Bool = false) -> Path {
    var p = Path()
    p.addArc(center: o, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: hole)
    p.closeSubpath()
    return p
}

    func ring(_ o: CGPoint, _ outer: CGFloat, _ inner: CGFloat) -> Path {
    var p = circle(o, outer)
    if inner > 0 { p.addPath(circle(o, inner, hole: true)) }
    return p
}

    func heart(_ o: CGPoint, _ size: CGFloat, hole: Bool = false) -> Path {
    poly((0..<28).map { k in
        let t = CGFloat(k) / 28 * 2 * .pi, s = sin(t), u = size / 16
        let a: CGFloat = 13 * cos(t) - 5 * cos(2 * t)
        let b: CGFloat = 2 * cos(3 * t) + cos(4 * t)
        return CGPoint(x: o.x + 16 * s * s * s * u, y: o.y - (a - b + 2.5) * u)
    }, hole: hole)
}

    func star(_ o: CGPoint, _ r: CGFloat) -> Path {
    poly((0..<10).map { k in
        let a = CGFloat(k) * .pi / 5 - .pi / 2, d = k % 2 == 0 ? r : r * 0.45
        return CGPoint(x: o.x + cos(a) * d, y: o.y + sin(a) * d)
    })
}

    func fluff(_ o: CGPoint, _ r: CGFloat) -> Path {
    var p = oval(o.x, o.y, r * 0.72, r * 0.72)
    for k in 0..<8 {
        let a = CGFloat(k) * .pi / 4 + 0.3
        p.addPath(oval(o.x + cos(a) * r * 0.6, o.y + sin(a) * r * 0.6, r * 0.42, r * 0.42))
    }
    return p
}

}

extension Path {
    func turned(_ angle: CGFloat, _ o: CGPoint) -> Path {
        applying(CGAffineTransform(translationX: -o.x, y: -o.y).concatenating(CGAffineTransform(rotationAngle: angle)).concatenating(CGAffineTransform(translationX: o.x, y: o.y)))
    }
}

extension Path {
    var inside: [CGPoint] {
        let box = boundingRect, mid = CGPoint(x: box.midX, y: box.midY)
        var all = [mid]
        forEach { element in
            switch element {
            case .move(let to), .line(let to), .quadCurve(let to, _), .curve(let to, _, _):
                let reach = hypot(to.x - mid.x, to.y - mid.y), keep = reach > 0 ? max(0, reach - 0.3) / reach : 0
                all.append(CGPoint(x: mid.x + keep * (to.x - mid.x), y: mid.y + keep * (to.y - mid.y)))
            case .closeSubpath: break
            }
        }
        return all
    }

    var subpaths: [Path] {
        var parts: [Path] = []
        forEach { element in
            switch element {
            case .move(let to): parts.append(Path()); parts[parts.count - 1].move(to: to)
            case .line(let to): parts[parts.count - 1].addLine(to: to)
            case .quadCurve(let to, let control): parts[parts.count - 1].addQuadCurve(to: to, control: control)
            case .curve(let to, let c1, let c2): parts[parts.count - 1].addCurve(to: to, control1: c1, control2: c2)
            case .closeSubpath: parts[parts.count - 1].closeSubpath()
            }
        }
        return parts
    }
}
