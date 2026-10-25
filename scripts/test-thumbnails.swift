import AppKit
import CoreMedia
import Foundation

@main
enum TestThumbnails {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print((ok ? "ok" : "FAILED") + ": " + what)
        if !ok { failures += 1 }
    }

    static func ffmpeg() -> String? {
        ((ProcessInfo.processInfo.environment["FFMPEG"].map { [$0] } ?? []) + ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func make(_ ffmpeg: String, _ name: String, in folder: URL, _ arguments: [String]) -> URL {
        let url = folder.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y"] + arguments + [url.path]
        try! process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "ffmpeg could not make \(name)")
        return url
    }

    static func videoDescription(_ url: URL) -> CMFormatDescription? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let demuxer = try? Demuxer(name: url.lastPathComponent, size: lseek(fd, 0, SEEK_END), memoryLimit: 32 << 20) { buffer, count, offset in
            let read = pread(fd, buffer, Int(count), offset)
            return read < 0 ? -EIO : read == 0 ? PikaErrorEOF : Int32(read)
        }
        return demuxer?.streams.first { $0.format.mediaType == kCMMediaType_Video }?.format.description
    }

    static func wait(_ seconds: Double, until done: () -> Bool) {
        let end = Date(timeIntervalSinceNow: seconds)
        while !done(), Date() < end { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    static func average(_ data: [UInt8]) -> (r: Int, g: Int, b: Int) {
        var sum = (0, 0, 0)
        for i in stride(from: 0, to: data.count, by: 4) { sum = (sum.0 + Int(data[i]), sum.1 + Int(data[i + 1]), sum.2 + Int(data[i + 2])) }
        let count = data.count / 4
        return (sum.0 / count, sum.1 / count, sum.2 / count)
    }

    static func thumbnail(_ url: URL, size: CGSize, duration: Double, at fraction: Double) -> CGImage? {
        let thumbnails = Thumbnails(url: url, size: size, duration: duration)
        defer { thumbnails.close() }
        let bucket = PlayerThumbnail.bucket(fraction * duration, duration: duration)
        var ready = false
        thumbnails.onReady = { if $0 == bucket { ready = true } }
        precondition(thumbnails.image(for: bucket) == nil, "nothing is ready before the first request")
        wait(20) { ready }
        return ready ? thumbnails.image(for: bucket) : nil
    }

    static func fillAll(_ url: URL) -> (count: Int, released: Bool) {
        weak var gone: Thumbnails?
        var ready = Set<Int>()
        do {
            let thumbnails = Thumbnails(url: url, size: CGSize(width: 320, height: 180), duration: 10)
            gone = thumbnails
            thumbnails.onReady = { ready.insert($0) }
            _ = thumbnails.image(for: 50)
            wait(60) { ready.count == PlayerThumbnail.buckets }
            check(thumbnails.image(for: 0) != nil && thumbnails.image(for: 99) != nil, "a ready picture is returned at once")
            thumbnails.close()
        }
        wait(5) { gone == nil }
        return (ready.count, gone == nil)
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let ffmpeg = ffmpeg() else {
            print("skipped: no ffmpeg (set FFMPEG=/path/to/ffmpeg)")
            return
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pikapik-thumbnails-\(getpid())")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func finish(_ code: Int32) -> Never { try? FileManager.default.removeItem(at: folder); exit(code) }
        let picture = ["-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=10"]
        let clips: [(String, URL)] = [
            ("H.264 in MP4 (decoded by VideoToolbox)", make(ffmpeg, "h264.mp4", in: folder, picture + ["-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p"])),
            ("MPEG-4 in AVI (decoded by FFmpeg)", make(ffmpeg, "mpeg4.avi", in: folder, picture + ["-c:v", "mpeg4", "-g", "25", "-pix_fmt", "yuv420p"])),
            ("VP9 in WebM (decoded by FFmpeg)", make(ffmpeg, "vp9.webm", in: folder, picture + ["-c:v", "libvpx-vp9", "-g", "25", "-pix_fmt", "yuv420p"])),
        ]
        for (name, url) in clips {
            let middle = thumbnail(url, size: CGSize(width: 320, height: 180), duration: 10, at: 0.5)
            check(middle.map { $0.width == 320 && $0.height == 180 } ?? false, "\(name): the 50 % picture is 320 × 180, sharp on a Retina screen")
            let data = middle.map(pixels) ?? []
            let colors = Set(stride(from: 0, to: data.count, by: 4).map { (i: Int) -> Int in
                let red = Int(data[i]) << 16, green = Int(data[i + 1]) << 8
                return red | green | Int(data[i + 2])
            })
            check(colors.count > 50, "\(name): the picture is not empty")
            let start = thumbnail(url, size: CGSize(width: 320, height: 180), duration: 10, at: 0)
            check(start.map(pixels) != nil && start.map(pixels)! != data, "\(name): the start and the middle show different frames")
        }

        let red = make(ffmpeg, "red.mp4", in: folder, ["-f", "lavfi", "-i", "color=c=red:size=320x180:rate=25:duration=4", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        let color = thumbnail(red, size: CGSize(width: 320, height: 180), duration: 4, at: 0.5).map(pixels).map(average)
        check(color.map { $0.r > 200 && $0.g < 60 && $0.b < 60 } ?? false, "red stays red: \(String(describing: color))")

        let av1 = make(ffmpeg, "red-av1.mkv", in: folder, ["-f", "lavfi", "-i", "color=c=red:size=320x180:rate=25:duration=4", "-c:v", "libsvtav1", "-preset", "12", "-pix_fmt", "yuv420p"])
        let native = PikaCodec.nativeAV1
        for (name, description, videoToolbox) in [("AV1", native, true), ("AV1 on dav1d", false, true), ("AV1 that VideoToolbox refuses", true, false)] {
            (PikaCodec.nativeAV1, videoToolboxDecodesAV1) = (description, videoToolbox)
            let color = thumbnail(av1, size: CGSize(width: 320, height: 180), duration: 4, at: 0.5).map(pixels).map(average)
            check(color.map { $0.r > 200 && $0.g < 60 && $0.b < 60 } ?? false, "\(name): the preview is red: \(String(describing: color))")
            let engine = try? Engine(av1)
            engine?.muted = true
            engine?.seek(to: .zero, rate: 1)
            wait(5) { (engine?.synchronizer.currentTime().seconds ?? 0) > 1.5 }
            let reached = engine?.synchronizer.currentTime().seconds ?? 0
            check(engine?.hasVideo == true && engine?.failed == false && reached > 1.5, "\(name): the film plays without a decoding error: reached \(String(format: "%.1f", reached)) s")
            engine?.stop()
        }
        (PikaCodec.nativeAV1, videoToolboxDecodesAV1) = (native, true)

        let ntsc = make(ffmpeg, "ntsc.avi", in: folder, ["-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24000/1001:duration=60", "-c:v", "mpeg4", "-g", "24", "-pix_fmt", "yuv420p"])
        if let engine = try? Engine(ntsc) {
            engine.muted = true
            truncate(ntsc.path, 0)
            engine.seek(to: CMTime(seconds: 50, preferredTimescale: 600), rate: 1)
            wait(5) { engine.finished != nil }
            check(engine.finished != nil, "MPEG-4 in AVI at 23.976 fps: a seek after the file stops reading ends the film instead of crashing")
            engine.stop()
        } else {
            check(false, "MPEG-4 in AVI at 23.976 fps opens")
        }

        let fullColour = make(ffmpeg, "full-colour.mp4", in: folder, ["-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
                                                                      "-c:v", "libx264", "-pix_fmt", "yuv444p", "-c:a", "aac"])
        if let description = videoDescription(fullColour) {
            if videoToolboxDecodes(description) {
                let engine = try? Engine(fullColour)
                engine?.muted = true
                engine?.seek(to: .zero, rate: 1)
                wait(5) { (engine?.synchronizer.currentTime().seconds ?? 0) > 1.5 }
                check(engine?.hasVideo == true && engine?.layer.sampleBufferRenderer.status != .failed, "H.264 in 4:4:4, which this Mac decodes, plays with its picture")
                engine?.stop()
            } else {
                check((try? Engine(fullColour)) == nil, "H.264 in 4:4:4, which this Mac can't decode, is refused when it opens instead of playing its sound over a black picture")
            }
        } else {
            check(false, "H.264 in 4:4:4 has a video track")
        }

        let tall = make(ffmpeg, "tall.mp4", in: folder, ["-f", "lavfi", "-i", "testsrc2=size=180x320:rate=25:duration=4", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        let shape = thumbnail(tall, size: CGSize(width: 180, height: 320), duration: 4, at: 0.5)
        check(shape.map { $0.width == 100 && $0.height == 180 } ?? false, "a tall video keeps its shape: \(shape.map { "\($0.width) × \($0.height)" } ?? "none")")

        let (count, released) = fillAll(clips[0].1)
        check(count == PlayerThumbnail.buckets, "one hover fills all \(PlayerThumbnail.buckets) pictures in the background (\(count))")
        check(released, "closing frees the thumbnails")

        let chapterList = folder.appendingPathComponent("chapters.txt")
        try! Data(";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=4000\ntitle=One\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=4000\nEND=7000\ntitle=Two\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=7000\nEND=10000\n".utf8).write(to: chapterList)
        for container in ["mkv", "mp4"] {
            let url = make(ffmpeg, "chapters.\(container)", in: folder, picture + ["-i", chapterList.path, "-map_metadata", "1", "-map_chapters", "1", "-map", "0:v", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
            let found = (try? Engine(url))?.chapters ?? []
            check(found.map(\.start) == [0, 4, 7] && found.map(\.title) == ["One", "Two", ""], "\(container): chapters are read with their times and names: \(found.map { "\($0.start) \($0.title)" })")
        }
        check((try? Engine(clips[0].1))?.chapters.isEmpty == true, "a file without chapters has none")

        let audio = make(ffmpeg, "sound.mka", in: folder, ["-f", "lavfi", "-i", "sine=duration=4", "-c:a", "aac"])
        let broken = folder.appendingPathComponent("broken.mkv")
        try! Data("not a video".utf8).write(to: broken)
        for (name, url) in [("an audio file", audio), ("a broken file", broken)] {
            check(thumbnail(url, size: CGSize(width: 320, height: 180), duration: 4, at: 0.5) == nil, "\(name): no picture, nothing breaks")
        }
        print(failures == 0 ? "all thumbnail checks passed" : "\(failures) thumbnail checks FAILED")
        finish(failures == 0 ? 0 : 1)
    }
}
