import AppKit
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers

final class VideoView: NSView {
    weak var controller: PlayerController?
    weak var panel: NSView?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        controller?.showControls()
        guard let action = PlayerAction(key: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags, keyCode: event.keyCode), controller?.perform(action) == true else { return super.keyDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        controller?.scroll(event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = controller?.perform(.leaveFullScreen)
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.showControls()
    }

    override func mouseExited(with event: NSEvent) {
        controller?.hideControls()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if WindowChrome.stripDoubleClick(event, in: window) { return }
        if event.clickCount == 2 { _ = controller?.perform(.fullScreen) }
        if WindowChrome.startsDrag(event, in: window, at: convert(event.locationInWindow, from: nil), panel: panel) { window.performDrag(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: WindowChrome.trackingOptions, owner: self))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.playable(sender) == nil && Self.captions(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let media = Self.playable(sender), captions = Self.captions(sender)
        guard media != nil || !captions.isEmpty else { return false }
        if let media { controller?.load(media) }
        for url in captions { controller?.addSubtitle(url) }
        return true
    }

    static func files(_ sender: any NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func playable(_ sender: any NSDraggingInfo) -> URL? {
        files(sender).first { PlayerFormats.plays($0) || FolderAccess.isFolder($0) }
    }

    static func captions(_ sender: any NSDraggingInfo) -> [URL] {
        files(sender).filter { SubtitleFiles.extensions.contains($0.pathExtension.lowercased()) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { controller?.isMusic == true ? String(localized: "Music") : String(localized: "Video") }
    override func accessibilityValue() -> Any? { controller?.state }
}

final class Scrubber: NSSlider {
    var onHover: ((Double?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let knob = Double((cell as? NSSliderCell)?.knobThickness ?? 0), width = Double(bounds.width)
        let x = Double(convert(event.locationInWindow, from: nil).x)
        onHover?(max(0, min(1, (x - knob / 2) / max(width - knob, 1))))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }
}

final class PlayerController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static let volumeKey = "volume"
    static let resumeStore = "resume"
    static let minimum = NSSize(width: 640, height: 200)
    static let musicSize = NSSize(width: 640, height: 600)
    let video = VideoView()
    let music = MusicView()
    let message = NSTextField(labelWithString: String(localized: "Drop a video or a song here"))
    let controls = ControlPanel.make()
    let preview = ThumbnailPreview()
    let playButton = NSButton()
    let previousButton = NSButton()
    let nextButton = NSButton()
    let fullScreenButton = NSButton()
    let captionsButton = NSButton()
    let pipButton = NSButton()
    let airPlay = AirPlayLink()
    let speaker = NSImageView()
    let speedLabel = NSTextField(labelWithString: "")
    let elapsed = NSTextField(labelWithString: "0:00")
    let remaining = NSTextField(labelWithString: "-0:00")
    let scrubber = Scrubber(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let marks = TimeMarks()
    let volume = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    var engine: Engine?
    let subtitles = Subtitles()
    var chrome: WindowChrome?
    var observer: Any?
    var clockWatch: NSObjectProtocol?
    var thumbnails: Thumbnails?
    var pip: PictureInPicture?
    var hiddenForPip = false
    var chapters: [Chapter] = []
    var loop = PlayerLoop()
    var hovered: Double?
    var cursorHidden = false
    var playing = false
    var failed = false
    var isLast = false
    var declined = Set<String>()
    var track: [String: Any] = [:]
    var published: (Bool, Float)?
    var speed: Float = 1
    var muted = false
    var wheel = PlayerWheel()
    var resumeKey: String?
    var lastSaved = Date.distantPast
    var onClose: ((PlayerController) -> Void)?

    static var output: String?

    var isEmpty: Bool { engine == nil }

    func setOutput(_ uid: String?) {
        guard let engine, let target = uid ?? (engine.output == nil ? nil : PlayerOutput.system()), target != engine.output else { return }
        engine.route(to: target)
    }

    var isMusic: Bool { engine.map { !$0.hasVideo } ?? false }

    var state: String {
        if failed { return message.stringValue }
        guard let engine else { return message.stringValue }
        let now = PlayerTime.text(PlayerTime.clamp(engine.synchronizer.currentTime().seconds, duration: engine.duration.seconds)), total = PlayerTime.text(engine.duration.seconds)
        return playing ? String(localized: "Playing, \(now) of \(total)") : String(localized: "Paused, \(now) of \(total)")
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.collectionBehavior = .fullScreenPrimary
        window.minSize = Self.minimum
        window.backgroundColor = .black
        window.title = "pikapik Player"
        super.init(window: window)
        window.delegate = self
        build(window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func build(_ window: NSWindow) {
        video.controller = self
        video.panel = controls
        video.wantsLayer = true
        video.layer?.backgroundColor = NSColor.black.cgColor
        video.registerForDraggedTypes([.fileURL])
        window.contentView = video

        message.textColor = .white.withAlphaComponent(0.8)
        message.font = .systemFont(ofSize: 15, weight: .medium)
        message.alignment = .center
        message.lineBreakMode = .byTruncatingTail
        message.setAccessibilityElement(false)

        controls.appearance = NSAppearance(named: .darkAqua)

        configure(playButton, .playFill, String(localized: "Play"), #selector(playPause))
        configure(previousButton, .backwardFill, String(localized: "Previous in Folder"), #selector(previous))
        configure(nextButton, .forwardFill, String(localized: "Next in Folder"), #selector(next))
        configure(fullScreenButton, .arrowUpLeftAndArrowDownRight, String(localized: "Full Screen"), #selector(fullScreen))
        configure(captionsButton, .captionsBubble, String(localized: "Audio and Subtitles"), #selector(showTrackMenu))
        configure(pipButton, .pipEnter, String(localized: "Picture in Picture"), #selector(togglePictureInPicture))
        pipButton.isHidden = true
        for label in [elapsed, remaining, speedLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .labelColor
            label.setAccessibilityElement(false)
        }
        scrubber.target = self
        scrubber.action = #selector(scrub)
        scrubber.isContinuous = true
        scrubber.controlSize = .small
        scrubber.refusesFirstResponder = true
        scrubber.setAccessibilityLabel(String(localized: "Position"))
        scrubber.onHover = { [weak self] in self?.hover($0) }
        marks.translatesAutoresizingMaskIntoConstraints = false
        scrubber.addSubview(marks)
        speaker.image = NSImage(.speakerWave2Fill, accessibilityDescription: nil)
        speaker.contentTintColor = .labelColor
        speedLabel.isHidden = true
        volume.target = self
        volume.action = #selector(changeVolume)
        volume.controlSize = .small
        volume.refusesFirstResponder = true
        volume.setAccessibilityLabel(String(localized: "Volume"))
        volume.floatValue = UserDefaults.standard.object(forKey: Self.volumeKey) as? Float ?? 1

        airPlay.picker.isHidden = true
        airPlay.position = { [weak self] in self?.engine?.synchronizer.currentTime() ?? .zero }
        airPlay.onEvent = { [weak self] in self?.airPlayEvent($0) }
        let row = NSStackView(views: [previousButton, playButton, nextButton, elapsed, scrubber, remaining, speedLabel, speaker, volume, captionsButton, pipButton, airPlay.picker, fullScreenButton])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.setCustomSpacing(4, after: speaker)
        for view in [music, message, controls, row] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        video.addSubview(music)
        video.addSubview(message)
        video.addSubview(controls)
        video.addSubview(preview)
        subtitles.install(in: video, below: controls)
        subtitles.playing = { [weak self] in self?.playing == true }
        preview.isHidden = true
        let wide = controls.widthAnchor.constraint(equalToConstant: 560)
        wide.priority = .defaultHigh
        music.isHidden = true
        NSLayoutConstraint.activate([
            music.leadingAnchor.constraint(equalTo: video.leadingAnchor),
            music.trailingAnchor.constraint(equalTo: video.trailingAnchor),
            music.topAnchor.constraint(equalTo: video.topAnchor),
            music.bottomAnchor.constraint(equalTo: video.bottomAnchor),
            message.centerXAnchor.constraint(equalTo: video.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: video.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: video.widthAnchor, constant: -40),
            controls.centerXAnchor.constraint(equalTo: video.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: video.bottomAnchor, constant: -16),
            controls.heightAnchor.constraint(equalToConstant: 44),
            controls.widthAnchor.constraint(lessThanOrEqualTo: video.widthAnchor, constant: -32),
            wide,
            volume.widthAnchor.constraint(equalToConstant: 70),
            airPlay.picker.widthAnchor.constraint(equalToConstant: 22),
            airPlay.picker.heightAnchor.constraint(equalToConstant: 22),
            scrubber.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            marks.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),
            marks.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),
            marks.topAnchor.constraint(equalTo: scrubber.topAnchor),
            marks.bottomAnchor.constraint(equalTo: scrubber.bottomAnchor),
        ])
        ControlPanel.fill(controls, with: row)
        controls.isHidden = true
        chrome = WindowChrome(window, over: video)
    }

    func configure(_ button: NSButton, _ symbol: Symbol, _ label: String, _ action: Selector) {
        button.image = NSImage(symbol, accessibilityDescription: label)
        button.setAccessibilityLabel(label)
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.refusesFirstResponder = true
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
    }

    func load(_ url: URL, advancing: Bool = false) {
        guard !FolderAccess.isFolder(url) else { return openFolder(url) }
        stop()
        window?.title = url.lastPathComponent
        window?.representedURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        do {
            let engine = try Engine(url)
            self.engine = engine
            failed = false
            message.isHidden = true
            engine.volume = volume.floatValue
            engine.muted = muted
            if let output = Self.output { engine.route(to: output) }
            airPlay.open(url)
            airPlay.picker.isHidden = !engine.hasVideo
            engine.layer.frame = video.bounds
            engine.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            video.layer?.insertSublayer(engine.layer, at: 0)
            let tags = engine.tags(), cover = tags.cover.flatMap(NSImage.init(data:))
            if engine.hasVideo {
                fit(engine.size)
            } else {
                fitMusic()
            }
            if !engine.hasVideo { music.show(title: PlayerTags.title(tags.title, file: url), subtitle: PlayerTags.subtitle(artist: tags.artist, album: tags.album), cover: cover) }
            music.isHidden = engine.hasVideo
            track = Self.trackInfo(tags, cover: cover, file: url, hasVideo: engine.hasVideo, duration: engine.duration.seconds)
            let siblings = FolderAccess.files(in: url.deletingLastPathComponent())
            isLast = siblings.map { PlaylistOrder.neighbour(of: url, kind: PlayerFormats.kind(of: url) ?? .video, among: $0, step: 1) == nil } ?? false
            observer = engine.synchronizer.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in self?.tick() }
            playing = true
            chapters = engine.chapters
            refreshMarks()
            setUpPictureInPicture(engine)
            if engine.hasVideo, engine.duration.seconds > 0 {
                let thumbnails = Thumbnails(url: url, size: engine.size, duration: engine.duration.seconds)
                thumbnails.onReady = { [weak self] _ in self?.hover(self?.hovered) }
                self.thumbnails = thumbnails
            }
            resumeKey = Self.resumeKey(url)
            let resume = resumePosition(engine.duration.seconds)
            if engine.hasVideo { restoreTracks(of: url, resume: resume, siblings: siblings) }
            captionsButton.isHidden = !engine.hasVideo
            engine.seek(to: CMTime(seconds: resume, preferredTimescale: 90000), rate: speed)
            controls.isHidden = false
            update()
            showControls()
        } catch {
            fail(String(localized: "Can’t play this file. It may be damaged or in a format the player doesn’t support."))
            if advancing { go(1, explicit: false, advancing: true) }
        }
        NSAccessibility.post(element: video, notification: .valueChanged)
    }

    func openFolder(_ folder: URL) {
        FolderAccess.remember(folder)
        guard let first = FolderAccess.files(in: folder).flatMap(PlaylistOrder.first(among:)) else {
            stop()
            window?.title = folder.lastPathComponent
            window?.representedURL = nil
            fail(String(localized: "There is nothing to play in this folder."))
            return
        }
        load(first)
    }

    func fail(_ text: String) {
        failed = true
        message.stringValue = text
        message.isHidden = false
        music.isHidden = true
        controls.isHidden = true
        chrome?.setVisible(true, video: false)
    }

    static func trackInfo(_ tags: MediaTags, cover: NSImage?, file: URL, hasVideo: Bool, duration: Double) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: PlayerTags.title(tags.title, file: file),
            MPNowPlayingInfoPropertyMediaType: (hasVideo ? MPNowPlayingInfoMediaType.video : .audio).rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
        ]
        if let artist = PlayerTags.clean(tags.artist) { info[MPMediaItemPropertyArtist] = artist }
        if let album = PlayerTags.clean(tags.album) { info[MPMediaItemPropertyAlbumTitle] = album }
        if let cover { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover } }
        return info
    }

    func closeAirPlay() {
        airPlay.close()
    }

    func stop() {
        airPlay.close()
        stopClockWatch()
        volume.isEnabled = true
        guard let engine else { return }
        remember()
        thumbnails?.close()
        thumbnails = nil
        subtitles.close()
        preview.isHidden = true
        chapters = []
        loop = PlayerLoop()
        refreshMarks()
        pip?.close()
        pip = nil
        returnFromPictureInPicture()
        refreshPictureInPicture()
        resumeKey = nil
        if let observer { engine.synchronizer.removeTimeObserver(observer) }
        observer = nil
        engine.stop()
        engine.layer.removeFromSuperlayer()
        self.engine = nil
        playing = false
        published = nil
        track = [:]
        NowPlaying.shared.clear(self)
    }

    func fit(_ size: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main, size.width > 0, size.height > 0 else {
            window?.contentAspectRatio = .zero
            return
        }
        let room = screen.visibleFrame.insetBy(dx: 40, dy: 40).size
        let scale = min(1, room.width / size.width, room.height / size.height)
        window.contentAspectRatio = size
        place(NSSize(width: max(Self.minimum.width, (size.width * scale).rounded()), height: max(Self.minimum.height, (size.height * scale).rounded())))
    }

    func fitMusic() {
        window?.contentAspectRatio = .zero
        if !music.isHidden { return }
        place(Self.musicSize)
    }

    func place(_ content: NSSize) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
        if let screen = window.screen ?? NSScreen.main, !screen.visibleFrame.contains(window.frame) { window.center() }
    }

    func tick() {
        guard let engine else { return }
        let remote = airPlay.isActive
        if remote { airPlay.follow(engine.synchronizer) }
        if !remote, engine.failed, !failed {
            stop()
            fail(String(localized: "Can’t play this file. It may be damaged or in a format the player doesn’t support."))
            return
        }
        if !remote, engine.layer.sampleBufferRenderer.requiresFlushToResumeDecoding {
            engine.seek(to: engine.synchronizer.currentTime(), rate: rate)
        }
        let ended = engine.finished.map { engine.synchronizer.currentTime() >= $0 } ?? false
        if playing, let start = loop.wrap(at: ended ? .infinity : engine.position.seconds) {
            engine.seek(to: CMTime(seconds: start, preferredTimescale: 90000), rate: rate)
            update()
            return
        }
        if playing, Date().timeIntervalSince(lastSaved) >= 10 { remember() }
        if playing, let finished = engine.finished, engine.synchronizer.currentTime() >= finished {
            playing = false
            engine.synchronizer.rate = 0
            showControls()
            if !engine.hasVideo, !isLast { go(1, explicit: false, advancing: true) }
        }
        update()
    }

    func airPlayEvent(_ event: AirPlayLink.Event) {
        switch event {
        case .entered: enterAirPlay()
        case let .left(time, resume): leaveAirPlay(time, resume: resume)
        case let .playing(value): setPlaying(value)
        case let .problem(text): advise(text)
        }
    }

    func enterAirPlay() {
        guard let engine else { return }
        let time = engine.synchronizer.currentTime()
        engine.stop()
        engine.remote = { [weak self] time, rate in self?.airPlay.command(time: time, rate: rate) }
        clockWatch = NotificationCenter.default.addObserver(forName: AVSampleBufferRenderSynchronizer.rateDidChangeNotification, object: engine.synchronizer, queue: .main) { [weak self] _ in
            guard let self, let engine = self.engine else { return }
            self.airPlay.command(time: nil, rate: engine.synchronizer.rate)
        }
        engine.layer.isHidden = true
        message.stringValue = String(localized: "Playing on AirPlay")
        message.isHidden = false
        volume.isEnabled = false
        airPlay.command(time: time, rate: rate)
        engine.synchronizer.setRate(rate, time: time)
        update()
        showControls()
    }

    func leaveAirPlay(_ time: CMTime, resume: Bool) {
        stopClockWatch()
        volume.isEnabled = true
        guard let engine else { return }
        engine.remote = nil
        engine.layer.isHidden = false
        message.isHidden = true
        if !resume { playing = false }
        engine.seek(to: time, rate: rate)
        update()
        showControls()
    }

    func stopClockWatch() {
        if let clockWatch { NotificationCenter.default.removeObserver(clockWatch) }
        clockWatch = nil
    }

    func advise(_ text: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = AirPlayAdvice.title
        alert.informativeText = text
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    func update() {
        guard let engine else { return }
        let total = engine.duration.seconds, now = PlayerTime.clamp(engine.synchronizer.currentTime().seconds, duration: total)
        elapsed.stringValue = PlayerTime.text(now)
        remaining.stringValue = "-" + PlayerTime.text(total - now)
        scrubber.maxValue = max(total, 0.001)
        scrubber.doubleValue = now
        let label = playing ? String(localized: "Pause") : String(localized: "Play")
        playButton.image = NSImage(playing ? .pauseFill : .playFill, accessibilityDescription: label)
        playButton.setAccessibilityLabel(label)
        pip?.refresh()
        speedLabel.isHidden = speed == 1
        speedLabel.stringValue = "\(speed.formatted())×"
        speedLabel.setAccessibilityLabel(String(localized: "Speed"))
        nextButton.isEnabled = !isLast
        video.setAccessibilityValue(state)
        if published?.0 != playing || published?.1 != speed { publishNowPlaying() }
    }

    func publishNowPlaying() {
        guard let engine else { return }
        published = (playing, speed)
        var info = track
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = PlayerTime.clamp(engine.position.seconds, duration: engine.duration.seconds)
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(speed)
        NowPlaying.shared.publish(info, playing: playing, for: self)
    }

    var rate: Float { playing ? speed : 0 }

    var stepsByFrame: Bool { !playing && engine?.hasVideo == true }

}
