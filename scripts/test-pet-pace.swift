import CoreGraphics

enum PetStage { static let scale: CGFloat = 2.4 }

@main
enum TestPetPace {
    typealias State = PetPhysics.State

    static let screen = CGRect(x: 0, y: 4, width: 1440, height: 186)
    static let far = CGPoint(x: 1200, y: 600), above = CGPoint(x: 720, y: 80), onPet = CGPoint(x: 720, y: 20)

    struct Tally {
        var frames = 0, renders = 0, wakes = 0, lists = 0, docks = 0, probes = 0, peeks = 0
    }

    struct Stage {
        var physics: PetPhysics
        var mind = PetMind()
        var hidden = false, petCovered = false, lowPower = false, battery = false, rhythm = false
        var idle: (Double) -> Double = { _ in 0 }
        var mouse: (Double) -> CGPoint = { _ in TestPetPace.far }
        var paused = true, rate = 30, next = 0
        var alarm: Int?, peek: Int?, blind: Int?
        var last: Double?, waited = false, advanced = 0.0, felt = 0.0, blinked = 0.0, nextLook = 0.0, nextTalk = 700.0, nextAsk = 0.0
        var hover = (point: CGPoint.zero, at: -Double.infinity), probe: (point: CGPoint, time: Double)?
        var ignores = true, inside = false
        var pose = PetPose(), shift: CGFloat = 0, looping = false, baked = PetPose(), bakedAt: Double?
        var tally = [Tally](repeating: Tally(), count: 10), minute = 0
        var frames: [Double] = [], late = 0, rose = 0

        static func time(_ t: Int) -> Double { Double(t) / 600 }

        static func vsync(_ t: Int) -> Int { (t / 10 + 1) * 10 }

        static func same(_ a: PetPose, _ b: PetPose) -> Bool {
            var a = a
            a.squash = b.squash
            a.nap = b.nap
            return a == b
        }

        mutating func run(_ seconds: Double) {
            for t in 1..<Int(seconds * 600) {
                minute = t / 36000
                let now = Self.time(t)
                if t % 1200 == 0 { reconcile(t) }
                if let alarm, alarm <= t {
                    self.alarm = nil
                    tally[minute].wakes += 1
                    advance(t)
                }
                if let peek, peek <= t {
                    self.peek = nil
                    tally[minute].wakes += 1
                    tally[minute].peeks += 1
                    if near(now) { stir(t) } else { scout(t) }
                }
                if let blind, blind <= t {
                    self.blind = t + 120
                    tally[minute].wakes += 1
                    advance(t)
                }
                if !paused, next <= t {
                    tally[minute].frames += 1
                    frames.append(now)
                    advance(t)
                    if !paused { next = t + 600 / rate }
                }
                let inside = !ignores && physics.frame.contains(mouse(now))
                if self.inside, !inside, !ignores { stir(t) }
                self.inside = inside
            }
        }

        mutating func reconcile(_ t: Int) {
            let now = Self.time(t)
            tally[minute].lists += 1
            if PetPace.dock(now, next: nextAsk, moved: false) {
                tally[minute].docks += 1
                nextAsk = now + PetPace.recheck
            }
            if hidden || petCovered { ignores = true }
            pace(t)
        }

        mutating func stir(_ t: Int) {
            guard !hidden, paused else { return }
            (alarm, peek) = (nil, nil)
            paused = false
            next = Self.vsync(t)
        }

        mutating func scout(_ t: Int) {
            let now = Self.time(t)
            let wait = petCovered ? 0.5 : PetPace.glance(mouse(now), physics.frame, still: hover.at < now)
            peek = t + max(1, Int((wait * 600).rounded(.up)))
        }

        mutating func near(_ now: Double) -> Bool {
            let point = mouse(now)
            if hypot(point.x - hover.point.x, point.y - hover.point.y) > 2 { hover = (point, now) }
            guard now - hover.at < PetPace.linger else { return false }
            return !ignores || !petCovered && PetPace.near(point, physics.frame)
        }

        mutating func gauge(_ now: Double) -> PetPace {
            var pace = PetPace(hidden: hidden, covered: petCovered, baked: looping, lowPower: lowPower, battery: battery)
            if petCovered {
                if !physics.grounded { pace.flying = true }
            } else {
                pace.watch(physics, still: lowPower, at: advanced)
                if pose.lid < 1 {
                    pace.feel(mind.still(at: now))
                    pace.blink(after: blinked, at: now)
                }
                if pose.twinkle != 0 { pace.moving = true }
            }
            if !lowPower {
                pace.expect(nextLook, after: advanced)
                if physics.state == .doze, rhythm { pace.expect(felt + 1, after: advanced) }
            }
            if physics.state == .walk || physics.state == .rest { pace.expect(nextTalk, after: advanced) }
            pace.near = near(now)
            return pace
        }

        mutating func pace(_ t: Int) {
            let now = Self.time(t), pace = gauge(now)
            switch pace.mode(at: now) {
            case .run(_, _, let preferred):
                rate = Int(preferred)
                (peek, blind, alarm) = (nil, nil, nil)
                if paused {
                    paused = false
                    next = Self.vsync(t)
                }
            case .blind:
                paused = true
                (peek, alarm) = (nil, nil)
                if blind == nil { blind = t + 120 }
            case .wait(let until, _):
                paused = true
                blind = nil
                waited = true
                alarm = until.isFinite ? max(t + 1, Int((until * 600).rounded(.up)) + 1) : nil
                if peek == nil { scout(t) }
            case .off:
                paused = true
                (blind, peek, alarm) = (nil, nil, nil)
                waited = true
                if pace.hidden { last = nil }
            }
        }

        mutating func pointer(_ now: Double) -> CGPoint {
            let point = mouse(now)
            guard physics.state != .held, PetPace.near(point, physics.frame) else { return point }
            if probe.map({ PetPace.ask(point, now, after: $0) }) ?? true {
                probe = (point, now)
                tally[minute].probes += 1
            }
            return point
        }

        mutating func advance(_ t: Int) {
            let now = Self.time(t)
            var dt = last.map { now - $0 } ?? 0
            last = now
            if waited {
                physics.wait(dt)
                physics.resize(physics.bounds)
                dt = 0
                waited = false
            }
            advanced = now
            let point = pointer(now)
            if lowPower {
                if physics.canSit { physics.doze() }
            } else if now >= felt + 0.25 {
                let quiet = rhythm ? idle(now) : 0
                physics.sense(idle: quiet, typed: rhythm ? quiet : .infinity, now - felt)
                felt = now
            }
            if petCovered, physics.grounded { physics.wait(dt) } else { physics.step(dt, cursor: point) }
            if now >= blinked + PetPace.blinks { blinked = now }
            _ = physics.drain()
            if now >= nextLook { nextLook = now + 60 }
            place(now)
            if ignores == (physics.touches(point) || physics.state == .held) { ignores.toggle() }
            bake(now)
            pace(t)
        }

        mutating func place(_ now: Double) {
            guard !petCovered else { return }
            let left = physics.origin.x - 36, snapped = (left * 2).rounded(.down) / 2
            if left - snapped != shift {
                shift = left - snapped
                render()
            }
            var fresh = PetPose(physics, scale: PetStage.scale, time: now, blink: now - blinked < PetPace.shut, still: lowPower)
            fresh.face = mind.face(at: now)
            fresh.twinkle = fresh.face.glow > 0 && !physics.calm && !lowPower ? now : 0
            if fresh.lid >= 1 {
                fresh.face = PetFace()
                fresh.twinkle = 0
            }
            if physics.state == .sit, physics.hold - physics.clock < 0.25 { rose += 1 }
            if !looping || !Self.same(fresh, baked), fresh != pose {
                pose = fresh
                render()
            }
        }

        mutating func render() {
            looping = false
            tally[minute].renders += 1
            if bakedAt != nil { late += 1 }
        }

        mutating func bake(_ now: Double) {
            guard !looping, !petCovered, !lowPower, !physics.calm, physics.state == .doze, physics.clock >= 2.6 else { return }
            baked = PetPose(physics, scale: PetStage.scale, time: now, blink: false)
            looping = true
            bakedAt = bakedAt ?? now
        }
    }

    static func simulate(_ seconds: Double = 600, _ setup: (inout Stage) -> Void) -> Stage {
        var stage = Stage(physics: PetPhysics(bounds: screen))
        setup(&stage)
        stage.advance(0)
        (stage.tally, stage.frames, stage.rose) = ([Tally](repeating: Tally(), count: 10), [], 0)
        stage.run(seconds)
        return stage
    }

    static func touch(_ t: Double) -> CGPoint {
        func mix(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f) }
        switch t {
        case ..<300: return far
        case ..<301: return mix(far, onPet, t - 300)
        case ..<302: return onPet
        case ..<302.5: return mix(onPet, far, 2 * (t - 302))
        default: return far
        }
    }

    static func watched(_ pet: PetPhysics, still: Bool = false) -> (Bool, Bool, Bool, Double, Double) {
        var pace = PetPace()
        pace.watch(pet, still: still, at: 100)
        return (pace.flying, pace.moving, pace.dozing, pace.due, pace.edge)
    }

    static func reach(_ pet: PetPhysics, _ state: State) -> PetPhysics {
        var pet = pet
        for _ in 0..<1200 where pet.state != state { pet.step(1.0 / 120, cursor: nil) }
        precondition(pet.state == state, "never reached \(state)")
        return pet
    }

    static func aged(_ pet: PetPhysics, _ seconds: Double) -> PetPhysics {
        var pet = pet
        pet.wait(seconds)
        return pet
    }

    static func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        let fill = String(repeating: " ", count: max(0, width - text.count))
        return left ? text + fill : fill + text
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        rules()
        watches()
        minds()
        calm()
        loop()
        stage()
    }

    static func rules() {
        let top = PetPace.Mode.run(minimum: 15, maximum: 30, preferred: 30), low = PetPace.Mode.run(minimum: 15, maximum: 20, preferred: 20)
        precondition(PetPace(hidden: true, near: true, flying: true).mode(at: 0) == .off)
        precondition(PetPace(covered: true, near: true, moving: true).mode(at: 0) == .off)
        precondition(PetPace(covered: true, flying: true).mode(at: 0) == .blind)
        print("hidden or covered is off, covered in flight is blind: ok")
        precondition([PetPace(near: true), PetPace(flying: true), PetPace(moving: true), PetPace(edge: 10.1)].allSatisfy { $0.mode(at: 10) == top })
        precondition(PetPace(moving: true, battery: true).mode(at: 0) == low && PetPace(near: true, lowPower: true).mode(at: 0) == low)
        print("runs at 30, at 20 on battery or in Low Power Mode: ok")
        let doze = PetPace.Mode.run(minimum: 8, maximum: 15, preferred: 12)
        precondition(PetPace(dozing: true).mode(at: 0) == doze && PetPace(dozing: true, battery: true).mode(at: 0) == doze)
        precondition(PetPace(moving: true, dozing: true).mode(at: 0) == top && PetPace(dozing: true, baked: true).mode(at: 0) == .wait(until: .infinity, slack: 0))
        print("dozes at 12 until the loop is baked: ok")
        precondition(PetPace(due: 20, edge: 15).mode(at: 10) == .wait(until: 15 - PetPace.lead, slack: 0))
        precondition(PetPace(due: 15 - PetPace.lead, edge: 15).mode(at: 10) == .wait(until: 15 - PetPace.lead, slack: 0))
        print("an alarm before an animation edge has no slack: ok")
        precondition(PetPace(due: 12).mode(at: 10) == .wait(until: 12, slack: PetPace.slack * 2))
        precondition(PetPace(due: 12, edge: 12.3).mode(at: 10) == .wait(until: 12, slack: 12.3 - PetPace.lead - 12))
        precondition(PetPace(due: 9).mode(at: 10) == .wait(until: 9, slack: 0))
        print("a due alarm gets 15% slack, capped at the edge: ok")
        var moving = PetPace(), held = PetPace(edge: 9), calm = PetPace()
        moving.feel(nil)
        held.feel(5)
        calm.feel(.infinity)
        precondition(moving.moving && !held.moving && held.edge == 5 && !calm.moving && calm.edge == .infinity)
        print("feel: an animating face moves, a held face sets the edge: ok")
        var shut = PetPace(), open = PetPace(), early = PetPace(due: 12)
        shut.blink(after: 10, at: 10.05)
        open.blink(after: 10, at: 11)
        early.blink(after: 10, at: 11)
        precondition(shut.due == 10 + PetPace.shut && open.due == 10 + PetPace.blinks && early.due == 12)
        print("blink: due to open the eyes, then due at the next blink: ok")
        var expect = PetPace(), past = PetPace()
        expect.expect(5, 10, 20, 12, after: 10)
        past.expect(3, 10, after: 10)
        precondition(expect.due == 12 && past.due == .infinity)
        print("expect ignores past times: ok")
        let body = CGRect(x: 100, y: 4, width: 30, height: 32), r = 2 * PetPhysics.reach
        precondition(PetPace.near(CGPoint(x: 101 - r, y: 20), body) && !PetPace.near(CGPoint(x: 99 - r, y: 20), body))
        precondition(PetPace.near(CGPoint(x: 115, y: 35 + r), body) && !PetPace.near(CGPoint(x: 115, y: 37 + r), body))
        print("near: the body grown by twice the reach: ok")
        let gaps: [CGFloat] = [0, 200, 400, 1000, 2000, 9000]
        let glances = gaps.map { PetPace.glance(CGPoint(x: 130 + r + $0, y: 20), body, still: false) }
        precondition(PetPace.glance(CGPoint(x: 115, y: 20), body, still: true) == 0.5 && PetPace.glance(CGPoint(x: 5000, y: 20), body, still: true) == 0.5)
        precondition(glances.first == PetPace.peek && glances[3] == 0.25 && glances.last == 0.5 && glances == glances.sorted())
        print("glance: 0.5 s while still, 0.1-0.5 s by distance: ok")
        let last = (point: CGPoint(x: 50, y: 50), time: 0.0)
        precondition(!PetPace.ask(CGPoint(x: 52, y: 50), 1, after: last) && !PetPace.ask(CGPoint(x: 53, y: 50), 0.05, after: last) && PetPace.ask(CGPoint(x: 53, y: 50), 0.1, after: last))
        print("ask: only after a move over 2 pt and 0.1 s: ok")
        precondition(PetPace.dock(10, next: 30, moved: true) && PetPace.dock(30, next: 30, moved: false) && !PetPace.dock(29, next: 30, moved: false))
        print("dock: when the screens move or every 30 s: ok")
    }

    static func watches() {
        let walk = PetPhysics(bounds: screen)
        var turn = walk, jump = walk, tumble = walk, held = walk, kick = walk, sit = walk, doze = walk, rest = walk
        var ball = BallPhysics(bounds: screen, x: walk.origin.x + 23)
        precondition(turn.face(walk.origin.x - 100) && jump.jump() && held.grab(at: CGPoint(x: walk.origin.x, y: 20)))
        precondition(kick.kick(&ball) && sit.sit(3) && doze.doze())
        tumble.bump(CGRect(x: walk.origin.x + 5, y: 10, width: 16, height: 22))
        var thrown = held
        thrown.release()
        rest.calm = true
        rest.step(1.0 / 30, cursor: nil)
        let lie = reach(tumble, .lie), getUp = reach(lie, .getUp)
        var wake = aged(doze, 2)
        precondition(wake.wake())
        precondition([turn, jump, tumble, held, thrown, kick, rest].map(\.state) == [.turn, .jump, .tumble, .held, .thrown, .kick, .rest])
        for pet in [jump, tumble, held, thrown] { precondition(watched(pet) == (true, false, false, .infinity, .infinity), "\(pet.state) does not fly") }
        for pet in [walk, turn, kick, getUp, wake] { precondition(watched(pet) == (false, true, false, .infinity, .infinity), "\(pet.state) does not move") }
        precondition(watched(lie) == (false, false, false, 100 + (lie.hold - lie.clock), .infinity))
        precondition(watched(rest) == (false, false, false, .infinity, .infinity))
        print("watch: flight flies, steps move, lying waits for its end, rest is still: ok")
        let mid = aged(sit, 1), end = aged(sit, 2.8)
        precondition(watched(sit) == (false, true, false, .infinity, .infinity) && watched(end) == (false, true, false, .infinity, .infinity))
        precondition(watched(mid) == (false, false, false, .infinity, 100 + (mid.hold - mid.clock) - 0.25))
        var calmSit = rest
        precondition(calmSit.sit(3))
        precondition(watched(calmSit) == (false, false, false, 100 + (calmSit.hold - calmSit.clock), .infinity))
        print("watch: a sit eases in and out and waits for the edge between, a calm sit waits for its end: ok")
        let settling = aged(doze, 0.7)
        precondition(watched(aged(doze, 0.5)) == (false, true, false, .infinity, .infinity) && watched(aged(doze, 1.5)) == (false, false, true, .infinity, .infinity))
        precondition(watched(aged(doze, 0.2), still: true) == (false, true, false, .infinity, .infinity))
        precondition(watched(settling, still: true) == (false, false, false, 100 + 1 - settling.clock, .infinity))
        precondition(watched(aged(doze, 1.5), still: true) == (false, false, false, .infinity, .infinity))
        var calmDoze = rest
        precondition(calmDoze.doze())
        let calmSettling = aged(calmDoze, 0.2)
        precondition(watched(calmSettling) == (false, false, false, 100 + 1 - calmSettling.clock, .infinity))
        precondition(watched(aged(calmDoze, 1.5)) == (false, false, false, .infinity, .infinity))
        print("watch: dozing runs, a still or calm doze waits for its Z: ok")
    }

    static func minds() {
        var mind = PetMind(), sleepy = PetMind()
        precondition(mind.still(at: 0) == .infinity)
        precondition(mind.feel(.happy, at: 10) && sleepy.feel(.sleepy, at: 10))
        let until = 10 + PetMood.happy.length
        precondition(mind.still(at: 10.1) == nil && mind.still(at: 11) == until && mind.still(at: until + 0.1) == nil && mind.still(at: until + PetMind.fall) == .infinity)
        precondition(sleepy.still(at: 11) == nil)
        print("mind: calm is static, a rising, falling or sleepy face animates, a held face is static until it ends: ok")
    }

    static func calm() {
        var pet = PetPhysics(bounds: screen, x: 300)
        pet.calm = true
        pet.step(1.0 / 30, cursor: nil)
        for _ in 0..<18_000 {
            pet.step(1.0 / 30, cursor: nil)
            precondition(pet.state == .rest && pet.origin.x == 300 && !pet.jump(), "a calm pet moved: \(pet.state) \(pet.origin)")
        }
        print("calm: ten idle minutes without a step or a jump: ok")
        precondition(pet.grab(at: CGPoint(x: 300, y: 20)))
        for i in 1...12 { pet.step(1.0 / 120, cursor: CGPoint(x: 300 + 1000 * CGFloat(i) / 120, y: 20 + 1000 * CGFloat(i) / 120)) }
        precondition(pet.state == .held && pet.origin.x > 350, "a calm pet did not follow the hand: \(pet.origin)")
        pet.release()
        let flung = pet.origin
        pet.step(1.0 / 30, cursor: nil)
        precondition(pet.state == .thrown && pet.origin != flung, "a calm pet was not thrown: \(pet.state)")
        for _ in 0..<300 { pet.step(1.0 / 30, cursor: nil) }
        precondition(pet.state == .rest, "a thrown calm pet landed into \(pet.state)")
        print("calm: the hand still carries and throws the pet, and it lands at rest: ok")
    }

    static func loop() {
        var pet = PetPhysics(bounds: screen)
        precondition(pet.doze())
        pet.wait(2.6)
        for i in 0..<130 {
            let a = aged(pet, Double(i) * 10.8 / 130), b = aged(a, 10.8)
            let p = PetPose(a, scale: PetStage.scale, time: 0, blink: false), q = PetPose(b, scale: PetStage.scale, time: 0, blink: false)
            let zs = (0..<3).map { k in (p.nap - 0.8 - Double(k) * 0.9, q.nap - 0.8 - Double(k) * 0.9) }
            precondition(Stage.same(p, q) && abs(p.squash - q.squash) < 1e-9 && zs.allSatisfy { $0.0 >= 0 && abs(($0.1 - $0.0) / 2.7 - 4) < 1e-9 }, "baked frame \(i) does not loop")
        }
        print("the baked doze loops seamlessly over 10.8 s with all three Zs: ok")
    }

    static func stage() {
        let sit = simulate {
            _ = $0.physics.sit(10_000)
            $0.mouse = { t in CGPoint(x: 720 + 500 * sin(0.9 * t), y: 600 + 200 * sin(1.3 * t)) }
        }
        let doze = simulate {
            $0.rhythm = true
            $0.idle = { _ in 1000 }
            _ = $0.physics.doze()
        }
        let mains = simulate(60) { _ in }
        let battery = simulate(60) { $0.battery = true }
        let low = simulate {
            $0.lowPower = true
            _ = $0.physics.doze()
            $0.physics.wait(2)
            $0.mouse = touch
        }
        let covered = simulate { $0.petCovered = true }
        let hidden = simulate { $0.hidden = true }
        let calm = simulate { $0.physics.calm = true }
        let moving = simulate {
            _ = $0.physics.sit(10_000)
            $0.mouse = { t in CGPoint(x: 720 + 80 * sin(1.6 * t), y: 90) }
        }
        let still = simulate {
            _ = $0.physics.sit(10_000)
            $0.mouse = { _ in above }
        }
        let away = simulate { _ = $0.physics.sit(10_000) }
        let rows: [(String, Int, Stage, Int)] = [
            ("sit, pointer far moves", 1800, sit, 10), ("doze from its start", 720, doze, 10), ("walk, mains", 1800, mains, 1),
            ("walk, battery", 1800, battery, 1), ("low power, touch 5:00", 1800, low, 10), ("pet covered", 1800, covered, 10),
            ("hidden", 0, hidden, 10), ("reduce motion", 1800, calm, 10), ("pointer moving near", 1800, moving, 10),
            ("pointer still near", 1800, still, 10), ("pointer still far", 1800, away, 10),
        ]
        let keys: [KeyPath<Tally, Int>] = [\.renders, \.wakes, \.lists, \.docks, \.probes, \.peeks]
        print(pad("link frames (display link ticks) in each minute", 89, left: true) + " | the most in one minute; wakeups = alarm + peek + blind timers")
        print(pad("", 23) + pad("today", 6) + (0..<10).map { pad("m\($0)", 6) }.joined() + " |" + ["renders", "wakeups", "lists", "dock", "probes", "peeks"].map { pad($0, 8) }.joined())
        for (name, today, stage, minutes) in rows {
            let used = stage.tally.prefix(minutes), cells = used.map { pad("\($0.frames)", 6) }.joined()
            print(pad(name, 23, left: true) + pad("\(today)", 6) + pad(cells, 60, left: true) + " |" + keys.map { key in pad("\(used.map { $0[keyPath: key] }.max() ?? 0)", 8) }.joined())
        }
        print(pad("today", 89, left: true) + " |" + ["-", "-", "90", "30", "1800", "-"].map { pad($0, 8) }.joined())

        var failed: [String] = []
        func limit(_ name: String, _ ok: Bool) {
            print("\(name): \(ok ? "ok" : "FAIL")")
            if !ok { failed.append(name) }
        }
        func each(_ stage: Stage, _ key: KeyPath<Tally, Int>, _ minutes: Int = 10, _ test: (Int) -> Bool) -> Bool {
            stage.tally.prefix(minutes).map { $0[keyPath: key] }.allSatisfy(test)
        }
        limit("covered or hidden: no link frames", each(covered, \.frames) { $0 == 0 } && each(hidden, \.frames) { $0 == 0 })
        limit("low power: link frames only within 5 s of the touch", !low.frames.isEmpty && low.frames.allSatisfy { (300...305).contains($0) })
        limit("walking: 1800 link frames a minute on mains, 1200 on battery", mains.tally[0].frames == 1800 && battery.tally[0].frames == 1200)
        limit("sitting: at most 60 link frames a minute", each(sit, \.frames) { $0 <= 60 })
        limit("dozing: at most 72 link frames a minute", each(doze, \.frames) { $0 <= 72 })
        limit("dozing: at most 2 link frames a minute after the first minute", doze.tally.dropFirst().allSatisfy { $0.frames <= 2 })
        limit("dozing: no renders after the bake", doze.bakedAt != nil && doze.late == 0)
        limit("reduce motion: at most 60 link frames a minute", each(calm, \.frames) { $0 <= 60 })
        limit("at most 30 window lists a minute", rows.allSatisfy { row in each(row.2, \.lists, row.3) { $0 <= 30 } })
        limit("at most 2 Dock queries a minute", rows.allSatisfy { row in each(row.2, \.docks, row.3) { $0 <= 2 } })
        limit("pointer moving near: at most 600 probes a minute", each(moving, \.probes) { $0 <= 600 })
        limit("pointer still: at most 1 probe a minute", each(still, \.probes) { $0 <= 1 } && each(away, \.probes) { $0 <= 1 })
        limit("pointer still far: at most 120 peeks a minute", each(away, \.peeks) { $0 <= 120 })
        let holds = Array(stride(from: 4.0, through: 8.0, by: 0.05))
        let missed = holds.filter { hold in simulate(hold + 1) { _ = $0.physics.sit(hold) }.rose < 3 }
        limit("every 4-8 s sit draws its stand-up" + (missed.isEmpty ? "" : " (\(missed.count) of \(holds.count) skip it)"), missed.isEmpty)
        precondition(failed.isEmpty, "over the limit: " + failed.joined(separator: "; "))
    }
}
