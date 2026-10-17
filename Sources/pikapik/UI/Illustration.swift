import AppKit
import SwiftUI

enum Art {
    static let height: CGFloat = 128
    static let radius: CGFloat = 12
    static let stage = CGSize(width: 300, height: 128)
    static let red = Color(red: 1, green: 0.37, blue: 0.34)
    static let yellow = Color(red: 1, green: 0.74, blue: 0.18)
    static let green = Color(red: 0.16, green: 0.78, blue: 0.25)

    static func metal(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark ? [Color(white: 0.46), Color(white: 0.30)] : [Color(white: 0.94), Color(white: 0.77)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct Hairline<Outline: InsettableShape, Style: ShapeStyle>: View {
    let shape: Outline
    let style: Style
    @Environment(\.displayScale) private var scale

    var body: some View {
        shape.strokeBorder(style, lineWidth: 1 / max(scale, 1))
    }
}

extension InsettableShape {
    func hairline(_ style: some ShapeStyle) -> some View {
        Hairline(shape: self, style: style)
    }
}

private struct ArtScale: ViewModifier {
    let factor: CGFloat
    @Environment(\.displayScale) private var scale

    func body(content: Content) -> some View {
        content.environment(\.displayScale, scale * factor).scaleEffect(factor)
    }
}

extension View {
    func artScale(_ factor: CGFloat) -> some View {
        modifier(ArtScale(factor: factor))
    }
}

struct IllustrationRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ArtCard { content }
            .hostedApart()
            .frame(maxWidth: .infinity)
            .frame(height: Art.height)
            .accessibilityHidden(true)
    }
}

extension IllustrationRow {
    init<Scene: View>(loop durations: [Double], replay: Int = 0, rest: Int? = nil, from tick: Int = 0, @ViewBuilder scene: @escaping (Int) -> Scene) where Content == ArtLoop<Scene> {
        self.init { ArtLoop(durations: durations, replay: replay, rest: rest, tick: tick, scene: scene) }
    }
}

struct ArtLoop<Scene: View>: View {
    let durations: [Double]
    var replay = 0
    var rest: Int?
    @State var tick = 0
    @ViewBuilder let scene: (Int) -> Scene

    var body: some View {
        scene(tick).loop($tick, durations, replay: replay, rest: rest)
    }
}

private struct ArtCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Art.radius, style: .continuous)
        let dark = scheme == .dark
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(dark ? 0.26 : 0.15), Color.accentColor.opacity(dark ? 0.09 : 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: shape
            )
            .clipShape(shape)
            .overlay(shape.hairline(Color.primary.opacity(0.08)))
    }
}

private struct ArtHost: NSViewRepresentable {
    let content: AnyView

    func makeNSView(context: Context) -> ArtHostingView {
        let view = ArtHostingView(rootView: AnyView(EmptyView()))
        view.sizingOptions = []
        view.show(content, context.environment)
        return view
    }

    func updateNSView(_ view: ArtHostingView, context: Context) {
        view.show(content, context.environment)
    }
}

private final class ArtHostingView: NSHostingView<AnyView> {
    private static let frameTime = 1.0 / 30
    private var rendered = 0.0
    private var waiting = false
    private var parked = false
    private var scrolling: NSObjectProtocol?
    private var constraintsDue = false
    private var updatingConstraints = false
    private var content = AnyView(EmptyView())
    private var environment = EnvironmentValues()
    private var playing = true

    func show(_ content: AnyView, _ environment: EnvironmentValues) {
        self.content = content
        self.environment = environment
        refresh()
    }

    private func refresh() {
        var environment = environment
        environment.artPlaying = playing
        rootView = AnyView(content.environment(\.self, environment))
    }

    private func play() {
        guard (shown >= 0.5) != playing else { return }
        playing.toggle()
        refresh()
    }

    override var needsUpdateConstraints: Bool {
        get { updatingConstraints }
        set { if newValue { constraintsDue = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scrolling.map(NotificationCenter.default.removeObserver)
        scrolling = enclosingScrollView.map {
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: $0.contentView, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.play()
                guard self.parked, self.shown > 0 else { return }
                self.parked = false
                self.needsLayout = true
            }
        }
    }

    override func layout() {
        let shown = shown
        if (shown >= 0.5) != playing { DispatchQueue.main.async { [weak self] in self?.play() } }
        guard shown > 0 else {
            parked = true
            return
        }
        let now = CACurrentMediaTime()
        let frame = ((now + 0.002) / Self.frameTime).rounded(.down)
        guard frame > rendered else {
            if !waiting {
                waiting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (frame + 1) * Self.frameTime - now) { [weak self] in
                    self?.waiting = false
                    self?.needsLayout = true
                }
            }
            return
        }
        rendered = frame
        if constraintsDue {
            constraintsDue = false
            updatingConstraints = true
            updateConstraintsForSubtreeIfNeeded()
            updatingConstraints = false
        }
        super.layout()
    }

    private var shown: CGFloat {
        guard let root = window?.contentView else { return 0 }
        let frame = convert(bounds, to: nil)
        var rect = frame.intersection(root.convert(root.bounds, to: nil))
        if let scroll = enclosingScrollView { rect = rect.intersection(scroll.convert(scroll.bounds, to: nil)) }
        return rect.isEmpty ? 0 : rect.width * rect.height / (frame.width * frame.height)
    }
}

struct Stage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack { content }
            .frame(width: Art.stage.width, height: Art.stage.height)
    }
}

private struct Loop: ViewModifier {
    @Binding var tick: Int
    let durations: [Double]
    let replay: Int
    let rest: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artPlaying) private var playing
    @State private var visible = true
    @State private var played = 0

    private struct Run: Equatable {
        let visible: Bool
        let reduceMotion: Bool
        let replay: Int
    }

    func body(content: Content) -> some View {
        content
            .settingsVisibility($visible)
            .task(id: Run(visible: visible && playing, reduceMotion: reduceMotion, replay: replay)) {
                let replaying = replay != played
                played = replay
                guard visible, playing, !reduceMotion || replaying else { return }
                if replaying { tick = 0 }
                var steps = reduceMotion ? rest ?? durations.count - 1 : Int.max
                var deadline = ContinuousClock.now
                while steps > 0, !Task.isCancelled {
                    deadline += .seconds(durations[tick % durations.count])
                    try? await Task.sleep(until: deadline, clock: .continuous)
                    guard !Task.isCancelled else { return }
                    tick += 1
                    steps -= 1
                }
            }
    }
}

struct ArtTimeline<Content: View>: View {
    @ViewBuilder var content: (Double?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artPlaying) private var playing
    @State private var visible = true
    @State private var shown = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !visible || !shown || !playing)) { context in
            content(reduceMotion ? nil : context.date.timeIntervalSinceReferenceDate)
        }
        .onAppear { shown = true }
        .onDisappear { shown = false }
        .settingsVisibility($visible)
    }
}

private struct ArtPlayingKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var artPlaying: Bool {
        get { self[ArtPlayingKey.self] }
        set { self[ArtPlayingKey.self] = newValue }
    }
}

extension View {
    func settingsVisibility(_ visible: Binding<Bool>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window === SettingsWindow.window else { return }
            visible.wrappedValue = window.occlusionState.contains(.visible)
        }
    }

    func hostedApart() -> some View {
        ArtHost(content: AnyView(self))
    }

    func loop(_ tick: Binding<Int>, _ durations: [Double], replay: Int = 0, rest: Int? = nil) -> some View {
        modifier(Loop(tick: tick, durations: durations, replay: replay, rest: rest))
    }

    func spring(_ value: some Equatable, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15), value: value)
    }
}

struct ChoiceTile<Content: View>: View {
    let title: String
    let selected: Bool
    var size = CGSize(width: 67, height: 44)
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                content
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .hairline(.separator)
                    }
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 3)
                                .padding(-4)
                        }
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
