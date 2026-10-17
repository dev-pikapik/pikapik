import AppKit
import CoreMedia

struct SubtitleScene: Equatable {
    var text: String?
    var pictures: [PictureCue] = []
}

final class SubtitleView: NSView {
    private let label = CATextLayer()
    private let assLayer = CALayer()
    private var stickers: [CALayer] = []
    private(set) var scene = SubtitleScene()
    private(set) var ass: AssFrame?
    private var raised: CGFloat = 0
    var shown: String? { scene.text }
    var onResize: () -> Void = {}
    var scale = 1.0 { didSet { relayout(animated: false) } }
    var videoSize = CGSize.zero { didSet { relayout(animated: false) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.alignmentMode = .center
        label.isWrapped = true
        label.truncationMode = .none
        label.shadowColor = NSColor.black.cgColor
        label.shadowOpacity = 0.95
        label.shadowRadius = 3
        label.shadowOffset = CGSize(width: 0, height: -1)
        label.isHidden = true
        assLayer.magnificationFilter = .linear
        assLayer.minificationFilter = .trilinear
        assLayer.isHidden = true
        layer?.addSublayer(label)
        layer?.addSublayer(assLayer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        relayout(animated: false)
        onResize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        relayout(animated: false)
    }

    func show(_ scene: SubtitleScene) {
        guard scene != self.scene else { return }
        self.scene = scene
        relayout(animated: false)
    }

    func show(_ text: String?) {
        show(SubtitleScene(text: text))
    }

    func show(ass: AssFrame?) {
        guard ass !== self.ass else { return }
        self.ass = ass
        relayout(animated: false)
    }

    func lift(_ inset: CGFloat) {
        guard inset != raised else { return }
        raised = inset
        relayout(animated: true)
    }

    var assCanvas: AssCanvas {
        let region = videoRect
        let factor = window?.backingScaleFactor ?? 2
        return AssCanvas(size: CGSize(width: (region.width * factor).rounded(), height: (region.height * factor).rounded()), video: videoSize, scale: scale)
    }

    private var videoRect: CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return bounds }
        let fit = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * fit, height: videoSize.height * fit)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func relayout(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        defer { CATransaction.commit() }
        let usable = bounds.width > 40 && bounds.height > 40
        layoutText(usable ? scene.text : nil)
        layoutPictures(usable ? scene.pictures : [])
        layoutAss(usable ? ass : nil)
    }

    private func layoutText(_ text: String?) {
        guard let text else {
            label.isHidden = true
            return
        }
        label.contentsScale = window?.backingScaleFactor ?? 2
        let attributed = Self.attributed(text, size: SubtitleStyle.fontSize(forHeight: Double(bounds.height), scale: scale))
        let rect = attributed.boundingRect(with: CGSize(width: bounds.width * 0.86, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: min(bounds.width, ceil(rect.width) + 8), height: ceil(rect.height) + 2)
        label.string = attributed
        label.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: max(raised, bounds.height * 0.05).rounded(), width: size.width, height: size.height)
        label.isHidden = false
    }

    private func place(_ canvas: CGSize, _ rects: [CGRect]) -> [CGRect] {
        let region = videoRect
        guard canvas.width > 0, canvas.height > 0 else { return [] }
        let (sx, sy) = (region.width / canvas.width, region.height / canvas.height)
        return rects.map { CGRect(x: region.minX + $0.minX * sx, y: region.maxY - $0.maxY * sy, width: $0.width * sx, height: $0.height * sy) }
    }

    private func lifted(_ rects: [CGRect]) -> [CGRect] {
        let lift = max(0, raised - (rects.map(\.minY).min() ?? raised))
        return rects.map { $0.offsetBy(dx: 0, dy: lift) }
    }

    private func layoutAss(_ frame: AssFrame?) {
        guard let frame, let rect = lifted(place(frame.canvas, [frame.rect])).first else {
            assLayer.isHidden = true
            return
        }
        assLayer.contents = frame.image
        assLayer.frame = rect
        assLayer.isHidden = false
    }

    private func layoutPictures(_ all: [PictureCue]) {
        let cues = all.filter { $0.canvas.width > 0 && $0.canvas.height > 0 }
        let images = cues.flatMap { $0.images.map(\.image) }
        let placed = lifted(cues.flatMap { place($0.canvas, $0.images.map(\.frame)) })
        while stickers.count < placed.count {
            let layer = CALayer()
            layer.magnificationFilter = .linear
            layer.minificationFilter = .trilinear
            self.layer?.addSublayer(layer)
            stickers.append(layer)
        }
        for (number, layer) in stickers.enumerated() {
            guard number < placed.count else {
                layer.isHidden = true
                continue
            }
            layer.contents = images[number]
            layer.frame = placed[number]
            layer.isHidden = false
        }
    }

    private static func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let result = NSMutableAttributedString()
        for span in SubtitleText.spans(text) {
            var traits: NSFontDescriptor.SymbolicTraits = []
            if span.italic { traits.insert(.italic) }
            if span.bold { traits.insert(.bold) }
            let font = traits.isEmpty ? base : NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
            result.append(NSAttributedString(string: span.text, attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: style]))
        }
        return result
    }
}

final class Subtitles {
    struct Entry {
        let id: String
        let title: String
        let language: String?
        var cues: SubtitleCues
        var pictures: [PictureCue] = []
        var ass: AssTrack?
        let available: Bool
    }

    private static let scaleKey = "subtitleScale"
    let view = SubtitleView()
    private(set) var tracks: [Entry] = []
    private(set) var selected: String?
    private(set) var chosen = false
    private(set) var delay = 0.0
    private(set) var scale: Double
    var position: () -> Double = { 0 }
    var playing: () -> Bool = { true }
    var ticking: Bool { timer != nil }
    private var scanner: SubtitleScanner?
    private var engine: AssEngine?
    private var generation = 0
    private var timer: Timer?
    private var interval = 0.0
    private var shown = SubtitleScene()
    private var flash: (text: String, until: Date)?
    private var decided = false
    private var saved = ""
    private var audioLanguage: String?
    private var loading = 0
    private var embeddedKnown = false

    init() {
        scale = SubtitleStyle.clampedScale(UserDefaults.standard.object(forKey: Self.scaleKey) as? Double ?? 1)
        view.scale = scale
        view.onResize = { [weak self] in self?.refresh() }
    }

    func install(in parent: NSView, below sibling: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view, positioned: .below, relativeTo: sibling)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    func open(_ file: URL, resume: Double, saved: String, delay: Double, audioLanguage: String?, neighbours: [URL]?) {
        close()
        self.delay = delay
        generation += 1
        let current = generation
        self.saved = saved
        self.audioLanguage = audioLanguage
        engine = AssEngine()
        for url in SubtitleFiles.matching(video: file, among: neighbours ?? []) { load(url, select: false) }
        scanner = SubtitleScanner(url: file, start: resume, onStreams: { [weak self] in
            guard let self, self.generation == current else { return }
            self.adopt($0)
        }, onCues: { [weak self] index, cues in
            guard let self, self.generation == current else { return }
            if let at = self.tracks.firstIndex(where: { $0.id == "e\(index)" }) { self.tracks[at].cues = SubtitleCues(cues) }
            self.refresh()
        }, onPictures: { [weak self] index, pictures in
            guard let self, self.generation == current else { return }
            if let at = self.tracks.firstIndex(where: { $0.id == "e\(index)" }) { self.tracks[at].pictures = pictures }
            self.refresh()
        }, engine: engine, onAss: { [weak self] _ in
            guard let self, self.generation == current else { return }
            self.refresh()
        })
    }

    func close() {
        generation += 1
        scanner?.cancel()
        scanner = nil
        engine = nil
        tracks = []
        selected = nil
        chosen = false
        decided = false
        delay = 0
        flash = nil
        loading = 0
        embeddedKnown = false
        saved = ""
        updateTimer()
        view.show(SubtitleScene())
        view.show(ass: nil)
        shown = SubtitleScene()
    }

    func load(_ url: URL, select: Bool, failed: (() -> Void)? = nil, done: (() -> Void)? = nil) {
        let current = generation
        let engine = engine
        loading += 1
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap(SubtitleParser.decode)
            let isASS = text.map(SubtitleParser.isASS) == true
            let script = isASS ? engine.flatMap { engine in text.flatMap { AssTrack(engine: engine, script: $0) } } : nil
            let usable = script?.isEmpty == false
            let cues = isASS ? [] : text.map(SubtitleParser.parse) ?? []
            DispatchQueue.main.async { [self] in
                guard generation == current else { return }
                loading -= 1
                guard !cues.isEmpty || usable else {
                    failed?()
                    return decide()
                }
                let id = "f:" + url.lastPathComponent
                let track = Entry(id: id, title: url.lastPathComponent, language: nil, cues: SubtitleCues(cues), ass: usable ? script : nil, available: true)
                if let at = tracks.firstIndex(where: { $0.id == id }) { tracks[at] = track } else { tracks.append(track) }
                if select {
                    choose(id)
                    done?()
                } else {
                    decide()
                }
            }
        }
    }

    func choose(_ id: String?) {
        selected = id.flatMap { id in tracks.contains { $0.id == id && $0.available } ? id : nil }
        chosen = true
        decided = true
        updateTimer()
        refresh()
    }

    func cycle() {
        let usable = tracks.filter(\.available).map(\.id)
        let next = selected.flatMap { usable.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        choose(next < usable.count ? usable[next] : nil)
    }

    func shift(by seconds: Double) {
        delay = ((delay + seconds) * 10).rounded() / 10
        announce(String(localized: "Subtitle Delay: \(delay.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))) s"))
    }

    func resize(by step: Double) {
        scale = SubtitleStyle.clampedScale(scale + step)
        UserDefaults.standard.set(scale, forKey: Self.scaleKey)
        view.scale = scale
        announce(String(localized: "Subtitle Size: \(scale.formatted(.percent.precision(.fractionLength(0))))"))
    }

    func refresh() {
        scanner?.cover(position())
        var scene = SubtitleScene()
        let track = selected.flatMap { id in tracks.first { $0.id == id } }
        if let flash, flash.until > Date() {
            scene.text = flash.text
        } else {
            flash = nil
            if let track {
                let moment = position() - delay
                scene.text = track.cues.text(at: position(), delay: delay)
                scene.pictures = track.pictures.filter { $0.start <= moment && $0.end > moment }
            }
        }
        updateTimer()
        if scene != shown {
            shown = scene
            view.show(scene)
        }
        drawAss(track?.ass)
    }

    private func drawAss(_ script: AssTrack?) {
        guard let script, let engine else {
            engine?.forget()
            return view.show(ass: nil)
        }
        let (current, id) = (generation, selected)
        engine.render(script, at: position() - delay, canvas: view.assCanvas) { [weak self] frame in
            guard let self, self.generation == current, self.selected == id else { return }
            self.view.show(ass: frame)
        }
    }

    func announce(_ message: String) {
        flash = (message, Date().addingTimeInterval(1.2))
        updateTimer()
        refresh()
    }

    private func adopt(_ streams: [SubtitleStream]) {
        embeddedKnown = true
        for (number, stream) in streams.enumerated() {
            let name = PlayerTracks.title(language: stream.language, name: stream.title, number: number + 1)
            let title = stream.format == nil ? String(localized: "\(name) (can’t be shown)") : name
            tracks.append(Entry(id: "e\(stream.index)", title: title, language: PlayerTracks.language(stream.language), cues: SubtitleCues([]), ass: stream.ass, available: stream.format != nil))
        }
        decide()
        refresh()
    }

    private func decide() {
        guard !decided, embeddedKnown, loading == 0 else { return }
        decided = true
        guard !chosen else { return }
        let usable = tracks.filter(\.available)
        switch saved {
        case "off": selected = nil
        case let id where usable.contains { $0.id == id }: selected = id
        default:
            if let external = usable.first(where: { $0.id.hasPrefix("f:") }) {
                selected = external.id
            } else if let at = PlayerTracks.preferred(among: usable.map(\.language)), usable[at].language != PlayerTracks.language(audioLanguage) {
                selected = usable[at].id
            }
        }
        updateTimer()
        refresh()
    }

    private func updateTimer() {
        let wanted = (selected != nil && playing()) || flash != nil
        let rate = tracks.first { $0.id == selected }?.ass == nil ? 0.05 : 1.0 / 30
        if !wanted || rate != interval {
            timer?.invalidate()
            timer = nil
        }
        if wanted, timer == nil {
            interval = rate
            timer = Timer(timeInterval: rate, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }
}
