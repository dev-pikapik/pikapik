import AppKit
import SwiftUI

final class FigureView<Pose: Equatable>: NSView {
    var pose: Pose { didSet { if pose != oldValue { render() } } }
    var shift: CGFloat = 0 { didSet { if shift != oldValue { render() } } }
    private let paint: (Pose, Bool, (Path, Color) -> Void) -> Void
    private var shapes: [CAShapeLayer] = []
    private var dark: Bool?
    private let environment = EnvironmentValues()
    private(set) var looping = false

    private var night: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    init(_ pose: Pose, paint: @escaping (Pose, Bool, (Path, Color) -> Void) -> Void) {
        self.pose = pose
        self.paint = paint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = .black
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowRadius = 1.5
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        render()
        PetStage.shared.stir()
    }

    override func viewDidChangeBackingProperties() {
        shapes.forEach { $0.contentsScale = window?.backingScaleFactor ?? 2 }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { render() }
    }

    private func render() {
        guard let layer else { return }
        let night = night
        let place = CGAffineTransform(translationX: bounds.midX + shift, y: PetStage.ground).scaledBy(x: PetStage.scale, y: -PetStage.scale)
        var index = 0
        let fill = { (path: Path, color: Color) in
            if index == self.shapes.count {
                let shape = CAShapeLayer()
                shape.contentsScale = self.window?.backingScaleFactor ?? 2
                layer.addSublayer(shape)
                self.shapes.append(shape)
            }
            self.shapes[index].path = path.applying(place).cgPath
            self.shapes[index].fillColor = color.resolve(in: self.environment).cgColor
            index += 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if looping {
            shapes.forEach { $0.removeAllAnimations() }
            looping = false
        }
        if dark != night {
            dark = night
            layer.shadowOpacity = night ? 0.5 : 0.22
        }
        paint(pose, night, fill)
        shapes[index...].forEach { $0.path = nil }
        CATransaction.commit()
    }

    func loop(_ poses: [Pose], over period: Double) {
        guard let layer, !poses.isEmpty else { return }
        let night = night
        let place = CGAffineTransform(translationX: bounds.midX + shift, y: PetStage.ground).scaledBy(x: PetStage.scale, y: -PetStage.scale)
        let frames = poses.map { pose in
            var frame: [(path: CGPath, color: CGColor)] = []
            paint(pose, night) { path, color in frame.append((path.applying(place).cgPath, color.resolve(in: self.environment).cgColor)) }
            return frame
        }
        let times = (0...poses.count).map { NSNumber(value: Double($0) / Double(poses.count)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dark != night {
            dark = night
            layer.shadowOpacity = night ? 0.5 : 0.22
        }
        while shapes.count < frames.map(\.count).max() ?? 0 {
            let shape = CAShapeLayer()
            shape.contentsScale = window?.backingScaleFactor ?? 2
            layer.addSublayer(shape)
            shapes.append(shape)
        }
        for (index, shape) in shapes.enumerated() {
            let paths = frames.map { index < $0.count ? $0[index].path : CGMutablePath() }
            let colors = frames.map { index < $0.count ? $0[index].color : .clear }
            shape.path = paths[0]
            shape.fillColor = colors[0]
            for (key, values) in [("path", paths as [AnyObject]), ("fillColor", colors as [AnyObject])] where values.contains(where: { !CFEqual($0, values[0]) }) {
                let animation = CAKeyframeAnimation(keyPath: key)
                animation.calculationMode = .discrete
                animation.values = values
                animation.keyTimes = times
                animation.duration = period
                animation.repeatCount = .infinity
                animation.isRemovedOnCompletion = false
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
                shape.add(animation, forKey: key)
            }
        }
        looping = true
        CATransaction.commit()
    }
}

final class PetHand: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseDown(with event: NSEvent) { PetStage.shared.grab(at: event.locationInWindow, in: window) }
    override func mouseDragged(with event: NSEvent) { NSCursor.closedHand.set() }
    override func mouseUp(with event: NSEvent) { PetStage.shared.drop() }
    override func mouseExited(with event: NSEvent) { PetStage.shared.stir() }
}

final class BubbleHost: NSHostingView<PetBubble> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PetBubble: View {
    let text: String
    let clickable: Bool
    var tail: CGFloat
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let paper = Color(nsColor: .windowBackgroundColor)
        VStack(spacing: -0.5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(text)
                if clickable {
                    Image(.arrowUpForwardCircleFill).foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 230)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(paper, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            BubbleTail()
                .fill(paper)
                .frame(width: 16, height: 8)
                .offset(x: tail)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { if clickable { action() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(clickable ? .isButton : [])
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX - 1, y: rect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX + 1, y: rect.minY + 2))
            path.closeSubpath()
        }
    }
}
