import AppKit
import CoreMedia

final class SubtitleScanner {
    private let url: URL
    private let onStreams: ([SubtitleStream]) -> Void
    private let onCues: (Int32, [SubtitleCue]) -> Void
    private let onPictures: (Int32, [PictureCue]) -> Void
    private let onAss: (Int32) -> Void
    private let engine: AssEngine?
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var stopped = false
    private var planned: (from: Double, to: Double)
    private var jump: Double?
    private var playhead = 0.0
    private var stalledAt: Double?
    private static let lead = 30.0
    private static let window = 600.0
    private static let margin = 60.0
    private let pictureBudget: Int

    private struct Reader {
        let format: SubtitleFormat
        let scale: Double
        let pictures: PictureDecoder?
        let ass: AssTrack?
    }

    init(url: URL, start: Double, onStreams: @escaping ([SubtitleStream]) -> Void, onCues: @escaping (Int32, [SubtitleCue]) -> Void, onPictures: @escaping (Int32, [PictureCue]) -> Void = { _, _ in }, engine: AssEngine? = nil, onAss: @escaping (Int32) -> Void = { _ in }, pictureBudget: Int = 32 << 20) {
        self.url = url
        self.engine = engine
        self.onAss = onAss
        self.pictureBudget = pictureBudget
        self.onStreams = onStreams
        self.onCues = onCues
        self.onPictures = onPictures
        let from = max(0, start - Self.lead)
        planned = (from, from + Self.lead + Self.window)
        jump = from
        playhead = start
        DispatchQueue.global(qos: .utility).async { self.run() }
    }

    func cancel() {
        lock.withLock { stopped = true }
        wake.signal()
    }

    func cover(_ position: Double) {
        let signal = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            playhead = position
            if position >= planned.from, position <= planned.to {
                if let at = stalledAt {
                    guard position - at >= 5 else { return false }
                    stalledAt = nil
                    return true
                }
                guard position > planned.to - Self.margin else { return false }
                planned.to += Self.window
            } else {
                let from = max(0, position - Self.lead)
                planned = (from, from + Self.lead + Self.window)
                jump = from
                stalledAt = nil
            }
            return true
        }
        if signal { wake.signal() }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func deliver(_ streams: [SubtitleStream]) {
        DispatchQueue.main.async { [onStreams] in onStreams(streams) }
    }

    private static func track(_ stream: UnsafeMutablePointer<AVStream>, in engine: AssEngine?) -> AssTrack? {
        let parameters = stream.pointee.codecpar.pointee
        guard let engine, parameters.extradata_size > 0, let header = parameters.extradata else { return nil }
        return AssTrack(engine: engine, header: Data(bytes: header, count: Int(parameters.extradata_size)))
    }

    private static func font(_ stream: UnsafeMutablePointer<AVStream>) -> (name: String, data: Data)? {
        let parameters = stream.pointee.codecpar.pointee
        guard parameters.extradata_size > 0, Int(parameters.extradata_size) <= AssEngine.fontFileLimit, let bytes = parameters.extradata else { return nil }
        let name = streamTag(stream, "filename") ?? "font"
        let kind = streamTag(stream, "mimetype")?.lowercased() ?? ""
        guard ["ttf", "otf", "ttc", "otc"].contains((name as NSString).pathExtension.lowercased()) || ["font", "truetype", "opentype"].contains(where: kind.contains) else { return nil }
        return (name, Data(bytes: bytes, count: Int(parameters.extradata_size)))
    }

    private func run() {
        defer { engine?.finishFonts() }
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return deliver([]) }
        defer { close(descriptor) }
        let reader = ByteReader(size: lseek(descriptor, 0, SEEK_END)) { buffer, count, offset in
            let read = pread(descriptor, buffer, Int(count), offset)
            return read < 0 ? -EIO : read == 0 ? PikaErrorEOF : Int32(read)
        }
        defer { withExtendedLifetime(reader) {} }
        av_log_set_level(AV_LOG_QUIET)
        let bufferSize: Int32 = 1 << 16
        func release(_ io: UnsafeMutablePointer<AVIOContext>) {
            var io: UnsafeMutablePointer<AVIOContext>? = io
            av_freep(&io!.pointee.buffer)
            avio_context_free(&io)
        }
        guard let buffer = av_malloc(Int(bufferSize)),
              let io = avio_alloc_context(buffer.assumingMemoryBound(to: UInt8.self), bufferSize, 0, Unmanaged.passUnretained(reader).toOpaque(), readBytes, nil, seekBytes) else { return deliver([]) }
        var opened = avformat_alloc_context()
        opened?.pointee.pb = io
        guard avformat_open_input(&opened, url.lastPathComponent, nil, nil) == 0, let context = opened else {
            release(io)
            return deliver([])
        }
        defer {
            let io = context.pointee.pb
            var closing: UnsafeMutablePointer<AVFormatContext>? = context
            avformat_close_input(&closing)
            if let io { release(io) }
        }
        _ = avformat_find_stream_info(context, nil)
        let origin = context.pointee.start_time == PikaNoTimestamp ? 0 : Double(context.pointee.start_time) / Double(AV_TIME_BASE)
        var streams: [SubtitleStream] = []
        var active: [Int32: Reader] = [:]
        var clocks: [Int32: Double] = [:]
        var canvas = CGSize.zero
        for position in 0..<Int(context.pointee.nb_streams) {
            guard let stream = context.pointee.streams[position] else { continue }
            stream.pointee.discard = AVDISCARD_ALL
            if clocks.isEmpty, stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO, stream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC == 0, stream.pointee.time_base.den > 0 {
                stream.pointee.discard = AVDISCARD_NONKEY
                clocks[stream.pointee.index] = Double(stream.pointee.time_base.num) / Double(stream.pointee.time_base.den)
                canvas = CGSize(width: Int(stream.pointee.codecpar.pointee.width), height: Int(stream.pointee.codecpar.pointee.height))
            }
            if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_ATTACHMENT, let font = Self.font(stream) { engine?.addFont(name: font.name, data: font.data) }
            guard stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_SUBTITLE else { continue }
            var format = SubtitleFormat(stream.pointee.codecpar.pointee.codec_id)
            let script = format == .ass ? Self.track(stream, in: engine) : nil
            if format == .ass, script == nil { format = nil }
            streams.append(SubtitleStream(index: stream.pointee.index, format: format, language: streamTag(stream, "language"), title: streamTag(stream, "title"), ass: script))
            if let format, stream.pointee.time_base.den > 0 {
                let pictures = format == .picture ? PictureDecoder(stream) : nil
                guard format != .picture || pictures != nil else { continue }
                stream.pointee.discard = AVDISCARD_DEFAULT
                active[stream.pointee.index] = Reader(format: format, scale: Double(stream.pointee.time_base.num) / Double(stream.pointee.time_base.den), pictures: pictures, ass: script)
            }
        }
        engine?.finishFonts()
        deliver(streams)
        guard !active.isEmpty, !isStopped else { return }
        var cues: [Int32: [SubtitleCue]] = [:]
        var seen = Set<String>()
        var changed = Set<Int32>()
        var assChanged = Set<Int32>()
        var stalled = false
        var pictures: [Int32: [Double: PictureCue]] = [:]
        var latest: [Int32: PictureCue] = [:]
        var picturesChanged = Set<Int32>()
        var pictureBytes = 0
        var lastDelivery = Date()
        func flush() {
            for index in changed {
                let copy = cues[index] ?? []
                DispatchQueue.main.async { [onCues] in onCues(index, copy) }
            }
            for index in picturesChanged {
                let copy = (pictures[index] ?? [:]).values.sorted { $0.start < $1.start }
                DispatchQueue.main.async { [onPictures] in onPictures(index, copy) }
            }
            for index in assChanged { DispatchQueue.main.async { [onAss] in onAss(index) } }
            changed = []
            assChanged = []
            picturesChanged = []
            lastDelivery = Date()
        }
        func store(_ index: Int32, _ event: PictureDecoder.Event) {
            if let last = latest[index], last.end > event.start, pictures[index]?[last.start] != nil {
                pictures[index]?[last.start] = last.ending(at: event.start)
                picturesChanged.insert(index)
            }
            latest[index] = nil
            guard !event.bitmaps.isEmpty else { return }
            let cue = PictureCue(start: event.start, end: event.start + event.duration, canvas: event.canvas, bitmaps: event.bitmaps)
            if let old = pictures[index]?[cue.start] { pictureBytes -= old.byteSize }
            pictures[index, default: [:]][cue.start] = cue
            pictureBytes += cue.byteSize
            latest[index] = cue
            picturesChanged.insert(index)
            while pictureBytes > pictureBudget {
                let all = pictures.flatMap { index, map in map.values.map { (index, $0) } }
                guard let far = all.max(by: { abs($0.1.start - cue.start) < abs($1.1.start - cue.start) }), far.1 !== cue else { break }
                pictures[far.0]?[far.1.start] = nil
                pictureBytes -= far.1.byteSize
                picturesChanged.insert(far.0)
            }
        }
        func relieve(_ track: AssTrack) -> Bool {
            let from = lock.withLock { playhead } - Self.lead
            track.prune(before: from)
            lock.withLock { planned.from = max(planned.from, from) }
            return !track.isFull
        }
        guard let packet = av_packet_alloc() else { return }
        defer {
            var freed: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&freed)
        }
        var reached = -Double.infinity
        func read(until limit: Double) {
            var failures = 0
            while !isStopped, lock.withLock({ jump == nil }) {
                let result = av_read_frame(context, packet)
                guard result >= 0 else {
                    failures += 1
                    if result == PikaErrorEOF || context.pointee.pb.pointee.error < 0 || failures > 64 {
                        reached = .infinity
                        lock.withLock { planned.to = .infinity }
                        return
                    }
                    continue
                }
                failures = 0
                defer { av_packet_unref(packet) }
                let index = packet.pointee.stream_index
                guard packet.pointee.pts != PikaNoTimestamp, packet.pointee.size > 0, let scale = active[index]?.scale ?? clocks[index] else { continue }
                let begin = Double(packet.pointee.pts) * scale - origin
                guard begin.isFinite else { continue }
                if let reader = active[index] {
                    if let decoder = reader.pictures {
                        if let event = decoder.decode(packet, begin: begin, scale: scale, fallback: canvas) { store(index, event) }
                    } else if let data = packet.pointee.data {
                        let length = packet.pointee.duration > 0 ? Double(packet.pointee.duration) * scale : 4
                        if let track = reader.ass {
                            track.add(UnsafeRawBufferPointer(start: data, count: Int(packet.pointee.size)), start: begin, duration: length)
                            assChanged.insert(index)
                            if track.isFull, !relieve(track) { stalled = true }
                        } else if let text = reader.format.text(Data(bytes: data, count: Int(packet.pointee.size))) {
                            let key = "\(index)|\(begin)|\(text)"
                            if seen.insert(key).inserted {
                                cues[index, default: []].append(SubtitleCue(start: begin, end: begin + length, text: text))
                                changed.insert(index)
                            }
                        }
                    }
                }
                reached = max(reached, begin)
                if Date().timeIntervalSince(lastDelivery) > 0.5 { flush() }
                if stalled {
                    lock.withLock { stalledAt = playhead }
                    return
                }
                if begin > limit { return }
            }
        }
        while !isStopped {
            let (target, limit) = lock.withLock { () -> (Double?, Double) in
                defer { jump = nil }
                return (jump, planned.to)
            }
            if let target {
                if av_seek_frame(context, -1, Int64((target + origin) * Double(AV_TIME_BASE)), AVSEEK_FLAG_BACKWARD) < 0 { av_seek_frame(context, -1, Int64(origin * Double(AV_TIME_BASE)), AVSEEK_FLAG_BACKWARD) }
                context.pointee.pb.pointee.error = 0
                for reader in active.values {
                    reader.pictures?.flush()
                    reader.ass?.flush()
                }
                latest = [:]
                reached = -.infinity
                stalled = false
            }
            if reached >= limit || stalled {
                flush()
                wake.wait()
                stalled = false
                continue
            }
            read(until: limit)
            flush()
        }
    }
}
