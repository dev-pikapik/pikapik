import CoreGraphics

struct PetPace {
    enum Mode: Equatable {
        case run(minimum: Float, maximum: Float, preferred: Float)
        case blind
        case wait(until: Double, slack: Double)
        case off
    }

    static let blinks = 3.8, shut = 0.13, peek = 0.1, lead = 0.15, linger = 1.3, slack = 0.15, recheck = 30.0

    var hidden = false, covered = false, near = false
    var flying = false, moving = false, dozing = false, baked = false
    var lowPower = false, battery = false
    var due = Double.infinity, edge = Double.infinity

    func mode(at now: Double) -> Mode {
        if hidden { return .off }
        if covered { return flying ? .blind : .off }
        let top: Float = lowPower || battery ? 20 : 30
        if flying || moving || near || edge - now <= Self.lead { return .run(minimum: 15, maximum: top, preferred: top) }
        if dozing, !baked { return .run(minimum: 8, maximum: 15, preferred: 12) }
        let start = edge - Self.lead
        if start <= due { return .wait(until: start, slack: 0) }
        return .wait(until: due, slack: min(Self.slack * max(due - now, 0), start - due))
    }

    mutating func watch(_ pet: PetPhysics, still: Bool, at now: Double) {
        let left = pet.hold - pet.clock
        switch pet.state {
        case .jump, .tumble, .held, .thrown:
            flying = true
        case .walk, .turn, .kick, .getUp, .wake:
            moving = true
        case .sit where pet.calm, .lie:
            due = min(due, now + left)
        case .sit:
            if pet.clock < 0.25 || left <= 0.25 { moving = true } else { edge = min(edge, now + left - 0.25) }
        case .doze where pet.calm || still:
            if pet.clock < 0.5, !pet.calm { moving = true } else if pet.clock <= 1 { due = min(due, now + 1 - pet.clock) }
        case .doze:
            if pet.clock <= 1 { moving = true } else { dozing = true }
        case .rest:
            break
        }
    }

    mutating func feel(_ still: Double?) {
        if let still { edge = min(edge, still) } else { moving = true }
    }

    mutating func blink(after blinked: Double, at now: Double) {
        due = min(due, now < blinked + Self.shut ? blinked + Self.shut : blinked + Self.blinks)
    }

    mutating func expect(_ times: Double..., after now: Double) {
        for time in times where time > now { due = min(due, time) }
    }

    static func near(_ point: CGPoint, _ body: CGRect) -> Bool {
        body.insetBy(dx: -2 * PetPhysics.reach, dy: -2 * PetPhysics.reach).contains(point)
    }

    static func glance(_ point: CGPoint, _ body: CGRect, still: Bool) -> Double {
        if still { return 0.5 }
        let zone = body.insetBy(dx: -2 * PetPhysics.reach, dy: -2 * PetPhysics.reach)
        let gap = hypot(max(zone.minX - point.x, 0, point.x - zone.maxX), max(zone.minY - point.y, 0, point.y - zone.maxY))
        return min(0.5, max(peek, gap / 4000))
    }

    static func ask(_ point: CGPoint, _ now: Double, after last: (point: CGPoint, time: Double)) -> Bool {
        hypot(point.x - last.point.x, point.y - last.point.y) > 2 && now - last.time >= peek
    }

    static func dock(_ now: Double, next: Double, moved: Bool) -> Bool {
        moved || now >= next
    }
}
