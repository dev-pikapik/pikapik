import AppKit
import CoreMedia

enum SubtitleFormat {
    case subrip, ass, webvtt, movText, picture

    init?(_ codec: AVCodecID) {
        switch codec {
        case AV_CODEC_ID_SUBRIP, AV_CODEC_ID_TEXT: self = .subrip
        case AV_CODEC_ID_ASS, AV_CODEC_ID_SSA: self = .ass
        case AV_CODEC_ID_WEBVTT: self = .webvtt
        case AV_CODEC_ID_MOV_TEXT: self = .movText
        case AV_CODEC_ID_HDMV_PGS_SUBTITLE, AV_CODEC_ID_DVD_SUBTITLE, AV_CODEC_ID_DVB_SUBTITLE:
            guard avcodec_find_decoder(codec) != nil else { return nil }
            self = .picture
        default: return nil
        }
    }

    func text(_ data: Data) -> String? {
        switch self {
        case .subrip: return nonEmpty(SubtitleText.clean(String(decoding: data, as: UTF8.self)))
        case .ass, .picture: return nil
        case .movText: return SubtitleParser.movText(data)
        case .webvtt:
            if data.count >= 8, ["vttc", "vtte"].contains(String(decoding: data[(data.startIndex + 4)..<(data.startIndex + 8)], as: UTF8.self)) { return SubtitleParser.webVTTBox(data) }
            return nonEmpty(SubtitleText.clean(String(decoding: data, as: UTF8.self)))
        }
    }

    private func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }
}

struct SubtitleStream {
    let index: Int32
    let format: SubtitleFormat?
    let language: String?
    let title: String?
    var ass: AssTrack?
}

struct PictureBitmap {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let indices: Data
    let palette: [UInt32]

    var image: CGImage? {
        guard width > 0, height > 0, indices.count >= width * height else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        indices.withUnsafeBytes { raw in
            for at in 0..<pixels.count { pixels[at] = palette[Int(raw[at])] }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 4) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

final class PictureCue: Equatable {
    let start: Double
    let end: Double
    let canvas: CGSize
    let bitmaps: [PictureBitmap]
    private var drawn: [(image: CGImage, frame: CGRect)]?

    init(start: Double, end: Double, canvas: CGSize, bitmaps: [PictureBitmap]) {
        self.start = start
        self.end = end
        self.canvas = canvas
        self.bitmaps = bitmaps
    }

    static func == (left: PictureCue, right: PictureCue) -> Bool { left === right }

    var byteSize: Int { bitmaps.reduce(0) { $0 + $1.indices.count } }

    func ending(at time: Double) -> PictureCue {
        let copy = PictureCue(start: start, end: max(start, min(end, time)), canvas: canvas, bitmaps: bitmaps)
        copy.drawn = drawn
        return copy
    }

    var images: [(image: CGImage, frame: CGRect)] {
        if drawn == nil {
            drawn = bitmaps.compactMap { bitmap in bitmap.image.map { ($0, CGRect(x: bitmap.x, y: bitmap.y, width: bitmap.width, height: bitmap.height)) } }
        }
        return drawn ?? []
    }
}

final class PictureDecoder {
    struct Event {
        let start: Double
        let duration: Double
        let canvas: CGSize
        let bitmaps: [PictureBitmap]
    }

    private var context: UnsafeMutablePointer<AVCodecContext>?

    init?(_ stream: UnsafeMutablePointer<AVStream>) {
        guard let codec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id), let context = avcodec_alloc_context3(codec) else { return nil }
        var opened: UnsafeMutablePointer<AVCodecContext>? = context
        guard avcodec_parameters_to_context(context, stream.pointee.codecpar) >= 0 else {
            avcodec_free_context(&opened)
            return nil
        }
        context.pointee.pkt_timebase = stream.pointee.time_base
        guard avcodec_open2(context, codec, nil) >= 0 else {
            avcodec_free_context(&opened)
            return nil
        }
        self.context = context
    }

    deinit { avcodec_free_context(&context) }

    func flush() { avcodec_flush_buffers(context) }

    func decode(_ packet: UnsafeMutablePointer<AVPacket>, begin: Double, scale: Double, fallback: CGSize) -> Event? {
        guard let context else { return nil }
        var subtitle = AVSubtitle()
        var got: Int32 = 0
        guard avcodec_decode_subtitle2(context, &subtitle, &got, packet) >= 0, got != 0 else { return nil }
        defer { avsubtitle_free(&subtitle) }
        var bitmaps: [PictureBitmap] = []
        for position in 0..<Int(min(subtitle.num_rects, 16)) {
            guard let rect = subtitle.rects?[position]?.pointee, rect.type == SUBTITLE_BITMAP, rect.w > 0, rect.h > 0, rect.w <= 8192, rect.h <= 8192,
                  let pixels = rect.data.0, let colors = rect.data.1, rect.linesize.0 >= rect.w else { continue }
            let width = Int(rect.w), height = Int(rect.h), stride = Int(rect.linesize.0)
            var indices = Data(count: width * height)
            indices.withUnsafeMutableBytes { target in
                for row in 0..<height { memcpy(target.baseAddress! + row * width, pixels + row * stride, width) }
            }
            var palette = [UInt32](repeating: 0, count: 256)
            let source = UnsafeRawPointer(colors)
            for at in 0..<min(max(Int(rect.nb_colors), 0), 256) {
                let color = source.loadUnaligned(fromByteOffset: at * 4, as: UInt32.self)
                let alpha = color >> 24
                func premultiplied(_ shift: UInt32) -> UInt32 { (((color >> shift) & 0xFF) * alpha + 127) / 255 }
                palette[at] = alpha << 24 | premultiplied(16) << 16 | premultiplied(8) << 8 | premultiplied(0)
            }
            bitmaps.append(PictureBitmap(x: Int(rect.x), y: Int(rect.y), width: width, height: height, indices: indices, palette: palette))
        }
        var canvas = CGSize(width: Int(context.pointee.width), height: Int(context.pointee.height))
        if canvas.width < 1 || canvas.height < 1 { canvas = fallback }
        if let right = bitmaps.map({ $0.x + $0.width }).max(), let bottom = bitmaps.map({ $0.y + $0.height }).max(), canvas.width < CGFloat(right) || canvas.height < CGFloat(bottom) {
            canvas = CGSize(width: max(canvas.width, CGFloat(right)), height: max(canvas.height, CGFloat(bottom)))
        }
        let shown = subtitle.end_display_time > subtitle.start_display_time ? Double(subtitle.end_display_time - subtitle.start_display_time) / 1000 : 0
        let duration = shown > 0 ? min(shown, 60) : packet.pointee.duration > 0 ? Double(packet.pointee.duration) * scale : 5
        return Event(start: begin + Double(subtitle.start_display_time) / 1000, duration: duration, canvas: canvas, bitmaps: bitmaps)
    }
}
