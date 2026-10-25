import AppKit
import AVFoundation
import CoreMedia

extension PlayerController {
    func perform(_ action: PlayerAction) -> Bool {
        switch action.resolved(playing: !stepsByFrame) {
        case .playPause: playPause(nil)
        case .skipBack: skip(-PlayerAction.skip)
        case .skipForward: skip(PlayerAction.skip)
        case .longBack: skip(-PlayerAction.longSkip)
        case .longForward: skip(PlayerAction.longSkip)
        case .frameBack: step(-1)
        case .frameForward: step(1)
        case .start: seek(0)
        case .end: seek(engine?.duration.seconds ?? 0)
        case .startOver: startOver()
        case .slower: setSpeed(PlayerSpeed.stepped(speed, -1))
        case .faster: setSpeed(PlayerSpeed.stepped(speed, 1))
        case .normalSpeed: setSpeed(1)
        case .louder: nudgeVolume(PlayerAction.volumeStep)
        case .quieter: nudgeVolume(-PlayerAction.volumeStep)
        case .mute: setMuted(!muted)
        case .fullScreen: fullScreen(nil)
        case .leaveFullScreen:
            guard window?.styleMask.contains(.fullScreen) == true else { return false }
            fullScreen(nil)
        case .snapshot: saveFrame()
        case .next: go(1, explicit: true)
        case .previous: previous(nil)
        case .floatOnTop: window?.level = window?.level == .floating ? .normal : .floating
        case .nextSubtitle, .nextAudio, .subtitleEarlier, .subtitleLater, .subtitleLarger, .subtitleSmaller: return performTrack(action)
        case .nextChapter: jumpChapter(1)
        case .previousChapter: jumpChapter(-1)
        case .loop: markLoop()
        case .pictureInPicture: togglePictureInPicture(nil)
        case .back, .forward: break
        }
        return true
    }

    @objc func menuAction(_ sender: NSMenuItem) {
        showControls()
        if let action = sender.representedObject as? PlayerAction { _ = perform(action) }
    }

    @objc func chooseSpeed(_ sender: NSMenuItem) {
        setSpeed(sender.representedObject as? Float ?? 1)
    }

    @objc func chooseChapter(_ sender: NSMenuItem) {
        guard chapters.indices.contains(sender.tag) else { return }
        seek(chapters[sender.tag].start)
        showControls()
    }

    @objc func moveToScreen(_ sender: NSMenuItem) {
        guard let window, let screen = sender.representedObject as? NSScreen else { return }
        let area = screen.visibleFrame
        let scale = min(1, area.width / window.frame.width, area.height / window.frame.height)
        let size = NSSize(width: (window.frame.width * scale).rounded(), height: (window.frame.height * scale).rounded())
        window.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true, animate: true)
    }

    @objc func playPause(_ sender: Any?) {
        guard let engine else { return }
        playing.toggle()
        if playing, let finished = engine.finished, engine.synchronizer.currentTime() >= finished {
            engine.seek(to: .zero, rate: speed)
        } else {
            engine.synchronizer.rate = rate
        }
        if !playing { remember() }
        update()
        subtitles.refresh()
        showControls()
    }

    func setPlaying(_ value: Bool) {
        if playing != value { playPause(nil) }
    }

    @objc func next(_ sender: Any?) {
        showControls()
        go(1, explicit: true)
    }

    @objc func previous(_ sender: Any?) {
        showControls()
        if let engine, engine.position.seconds > 3 {
            seek(0)
        } else {
            go(-1, explicit: true)
        }
    }

    func go(_ step: Int, explicit: Bool, advancing: Bool = false) {
        guard let url = window?.representedURL, let window else { return }
        let folder = url.deletingLastPathComponent()
        guard let files = FolderAccess.files(in: folder) else {
            guard explicit || !declined.contains(folder.path) else { return }
            declined.remove(folder.path)
            FolderAccess.ask(folder, in: window) { [weak self] granted in
                guard let self else { return }
                if granted { self.go(step, explicit: explicit, advancing: advancing) } else { self.declined.insert(folder.path) }
            }
            return
        }
        if let neighbour = PlaylistOrder.neighbour(of: url, kind: PlayerFormats.kind(of: url) ?? .video, among: files, step: step) {
            load(neighbour, advancing: advancing)
        } else if step > 0 {
            isLast = true
            update()
        }
    }

    @objc func fullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    func skip(_ seconds: Double) {
        guard let engine else { return }
        seek(engine.position.seconds + seconds)
        showControls()
    }

    func seek(_ seconds: Double) {
        guard let engine else { return }
        let target = PlayerTime.clamp(seconds, duration: engine.duration.seconds)
        if playing, let finished = engine.finished, engine.synchronizer.currentTime() >= finished { playing = false }
        engine.seek(to: CMTime(seconds: target, preferredTimescale: 90000), rate: rate)
        subtitles.refresh()
        scrubber.doubleValue = target
        elapsed.stringValue = PlayerTime.text(target)
        remaining.stringValue = "-" + PlayerTime.text(engine.duration.seconds - target)
        publishNowPlaying()
    }

    func step(_ direction: Int) {
        guard let engine else { return }
        if playing {
            playing = false
            engine.synchronizer.rate = 0
        }
        engine.step(direction)
        update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.subtitles.refresh() }
        showControls()
    }

    func setUpPictureInPicture(_ engine: Engine) {
        guard engine.hasVideo else { return }
        pip = PictureInPicture(layer: engine.layer, host: PictureInPicture.Host(
            duration: { [weak self] in self?.engine?.duration ?? .zero },
            isPlaying: { [weak self] in self?.playing ?? false },
            setPlaying: { [weak self] in if self?.playing != $0 { self?.playPause(nil) } },
            skip: { [weak self] in self?.skip($0) },
            changed: { [weak self] in self?.refreshPictureInPicture() },
            started: { [weak self] in self?.hideForPictureInPicture() },
            stopped: { [weak self] in self?.returnFromPictureInPicture() }
        ))
        refreshPictureInPicture()
    }

    func refreshPictureInPicture() {
        pipButton.isHidden = pip == nil
        pipButton.isEnabled = pip?.isPossible == true
        let label = pip?.isActive == true ? String(localized: "Exit Picture in Picture") : String(localized: "Picture in Picture")
        pipButton.image = NSImage(pip?.isActive == true ? .pipExit : .pipEnter, accessibilityDescription: label)
        pipButton.setAccessibilityLabel(label)
    }

    func hideForPictureInPicture() {
        guard let window, !window.styleMask.contains(.fullScreen), window.isVisible else { return }
        hiddenForPip = true
        window.orderOut(nil)
    }

    func returnFromPictureInPicture() {
        guard hiddenForPip else { return }
        hiddenForPip = false
        window?.makeKeyAndOrderFront(nil)
        showControls()
    }

    @objc func togglePictureInPicture(_ sender: Any?) {
        pip?.toggle()
    }

    func jumpChapter(_ direction: Int) {
        guard let engine, !chapters.isEmpty else { return }
        let starts = chapters.map(\.start), now = engine.position.seconds
        guard let target = direction > 0 ? PlayerChapters.next(starts, after: now) : PlayerChapters.previous(starts, before: now) else { return }
        seek(target)
        showControls()
    }

    func markLoop() {
        guard let engine else { return }
        loop.press(at: engine.position.seconds)
        refreshMarks()
        showControls()
    }

    func refreshMarks() {
        let total = engine?.duration.seconds ?? 0
        marks.chapters = PlayerChapters.fractions(chapters.map(\.start), duration: total)
        marks.loop = [loop.start, loop.end].compactMap { $0 }.map { total > 0 ? $0 / total : 0 }
    }

    var chapterNames: [String] {
        chapters.enumerated().map { $0.element.title.isEmpty ? String(localized: "Chapter \($0.offset + 1)") : $0.element.title }
    }

    private var currentChapter: Int? {
        engine.flatMap { PlayerChapters.current(chapters.map(\.start), at: $0.position.seconds) }
    }

    func startOver() {
        guard engine != nil else { return }
        playing = true
        seek(0)
        remember()
        update()
    }

    func setSpeed(_ value: Float) {
        speed = value
        if playing { engine?.synchronizer.rate = value }
        update()
        showControls()
    }

    func setMuted(_ value: Bool) {
        muted = value
        engine?.muted = value
        speaker.image = NSImage(value ? .speakerSlashFill : .speakerWave2Fill, accessibilityDescription: nil)
        showControls()
    }

    func nudgeVolume(_ step: Float) {
        volume.floatValue = PlayerTime.volume(volume.floatValue, by: step)
        changeVolume(nil)
        showControls()
    }

    func scroll(_ event: NSEvent) {
        guard engine != nil, event.momentumPhase.isEmpty else { return }
        let inverted = event.isDirectionInvertedFromDevice
        var (right, up) = (event.scrollingDeltaX * (inverted ? 1 : -1), event.scrollingDeltaY * (inverted ? -1 : 1))
        if event.modifierFlags.contains(.shift), right == 0 { (right, up) = (up, 0) }
        let change = wheel.add(right: right, up: up, precise: event.hasPreciseScrollingDeltas, began: event.phase == .began || event.phase == .mayBegin, at: event.timestamp)
        if change.volume != 0 {
            volume.floatValue = max(0, min(1, volume.floatValue + change.volume))
            changeVolume(nil)
            showControls()
        }
        if change.seconds != 0 { skip(change.seconds) }
    }

    func saveFrame() {
        guard let engine, let window else { return }
        let resume = playing
        playing = false
        engine.synchronizer.rate = 0
        update()
        let finish = { [weak self] in
            guard let self, resume, self.engine === engine else { return }
            self.playing = true
            engine.synchronizer.rate = self.speed
            self.update()
        }
        guard let image = engine.frameImage() else {
            frameFailed(finish)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = PlayerTime.snapshotName(window.representedURL?.lastPathComponent ?? "pikapik Player", at: engine.position.seconds)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return finish() }
            let saved = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil).map { destination in
                CGImageDestinationAddImage(destination, image, nil)
                return CGImageDestinationFinalize(destination)
            } ?? false
            if saved { finish() } else { self?.frameFailed(finish) }
        }
    }

    func frameFailed(_ finish: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn’t save the frame.")
        guard let window else { return finish() }
        alert.beginSheetModal(for: window) { _ in finish() }
    }

    static func resumeKey(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        return PlayerResume.key(path: url.standardizedFileURL.path, size: Int64(size), modified: modified)
    }

    func resumePosition(_ duration: Double) -> Double {
        guard let resumeKey, let saved = (UserDefaults.standard.dictionary(forKey: Self.resumeStore) as? [String: [Double]])?[resumeKey]?.first,
              PlayerResume.worthKeeping(saved, of: duration) else { return 0 }
        return saved
    }

    func remember() {
        lastSaved = Date()
        guard let engine, let resumeKey, engine.position.seconds.isFinite, engine.duration.seconds.isFinite else { return }
        let saved = UserDefaults.standard.dictionary(forKey: Self.resumeStore) as? [String: [Double]] ?? [:]
        UserDefaults.standard.set(PlayerResume.updated(saved, key: resumeKey, position: engine.position.seconds, duration: engine.duration.seconds, at: Date().timeIntervalSince1970), forKey: Self.resumeStore)
    }

    @objc func scrub(_ sender: Any?) {
        hover(nil)
        seek(scrubber.doubleValue)
        showControls()
    }

    @objc func changeVolume(_ sender: Any?) {
        if muted { setMuted(false) }
        engine?.volume = volume.floatValue
        UserDefaults.standard.set(volume.floatValue, forKey: Self.volumeKey)
    }

    func showControls() {
        guard engine != nil else {
            chrome?.setVisible(true, video: false)
            return
        }
        refreshControls(idle: 0)
        armHideTimer()
    }

    func armHideTimer() {
        chrome?.hideAfterIdle(PlayerChrome.hideDelay) { [weak self] in self?.refreshControls(idle: PlayerChrome.hideDelay) }
    }

    func hideControls() {
        refreshControls(idle: .infinity)
    }

    func refreshControls(idle: Double) {
        guard let window else { return }
        let location = window.mouseLocationOutsideOfEventStream
        let overControls = WindowChrome.overControls(window, at: location, panel: controls)
        let fullScreen = window.styleMask.contains(.fullScreen)
        let visible = PlayerChrome.visibility(playing: playing, overControls: overControls, fullScreen: fullScreen, idle: idle, hides: engine?.hasVideo ?? true)
        controls.animator().alphaValue = visible.controls ? 1 : 0
        subtitles.view.lift(visible.controls ? controls.frame.maxY + 10 : 0)
        chrome?.setVisible(visible.controls, video: engine?.hasVideo == true)
        if overControls, playing, idle >= PlayerChrome.hideDelay { armHideTimer() }
        if !visible.controls { hover(nil) }
        if visible.cursor == cursorHidden {
            cursorHidden = !visible.cursor
            NSCursor.setHiddenUntilMouseMoves(cursorHidden)
        }
    }

    func hover(_ fraction: Double?) {
        hovered = fraction
        guard let engine, let fraction else {
            preview.isHidden = true
            return
        }
        let total = engine.duration.seconds, seconds = fraction * total
        let chapter = PlayerChapters.current(chapters.map(\.start), at: seconds).map { chapterNames[$0] }
        preview.show(time: PlayerTime.text(seconds), image: thumbnails?.image(for: PlayerThumbnail.bucket(seconds, duration: total)), chapter: chapter)
        preview.setFrameSize(preview.fittingSize)
        let point = video.convert(NSPoint(x: scrubber.bounds.minX + CGFloat(fraction) * scrubber.bounds.width, y: 0), from: scrubber)
        preview.setFrameOrigin(NSPoint(x: max(8, min(video.bounds.width - preview.frame.width - 8, point.x - preview.frame.width / 2)), y: controls.frame.maxY + 8))
        preview.isHidden = false
        showControls()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseSpeed):
            item.state = item.representedObject as? Float == speed ? .on : .off
            return true
        case #selector(chooseAudio), #selector(chooseSubtitle), #selector(addSubtitleFile):
            return validateTrack(item)
        case #selector(chooseChapter):
            item.state = item.tag == currentChapter ? .on : .off
            return true
        case #selector(moveToScreen):
            item.state = item.representedObject as? NSScreen == window?.screen ? .on : .off
            return window?.styleMask.contains(.fullScreen) == false
        case #selector(menuAction):
            guard let action = item.representedObject as? PlayerAction else { return false }
            switch action {
            case .playPause: item.title = playing ? String(localized: "Pause") : String(localized: "Play")
            case .back: item.title = stepsByFrame ? String(localized: "Previous Frame") : String(localized: "Back 5 Seconds")
            case .forward: item.title = stepsByFrame ? String(localized: "Next Frame") : String(localized: "Forward 5 Seconds")
            case .mute: item.title = muted ? String(localized: "Unmute") : String(localized: "Mute")
            case .floatOnTop:
                item.state = window?.level == .floating ? .on : .off
                return true
            case .snapshot, .nextSubtitle, .subtitleEarlier, .subtitleLater, .subtitleLarger, .subtitleSmaller: return engine?.hasVideo == true
            case .nextAudio: return (engine?.audioTracks.count ?? 0) > 1
            case .next: return window?.representedURL != nil && !isLast
            case .previous: return window?.representedURL != nil
            case .nextChapter, .previousChapter: return !chapters.isEmpty
            case .pictureInPicture:
                item.title = pip?.isActive == true ? String(localized: "Exit Picture in Picture") : String(localized: "Picture in Picture")
                return pip?.isPossible == true
            case .loop: item.title = loop.isSet ? String(localized: "Clear Loop") : loop.start == nil ? String(localized: "Set Loop Start") : String(localized: "Set Loop End")
            default: break
            }
            return engine != nil
        default:
            return engine != nil
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        showControls()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        showControls()
    }

    func windowWillClose(_ notification: Notification) {
        hiddenForPip = false
        chrome?.cancelIdle()
        stop()
        scrubber.onHover = nil
        onClose?(self)
    }
}
