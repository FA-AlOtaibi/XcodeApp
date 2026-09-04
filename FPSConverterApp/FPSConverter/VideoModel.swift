import AVFoundation
import Foundation
import Photos
import FFmpegSupport

@MainActor
final class VideoModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case simple = "Fast"
        case smooth = "Smooth"
        var id: String { rawValue }
    }

    enum Quality: String, CaseIterable, Identifiable {
        case enhanced = "Enhanced"
        case twoK = "2K"
        case fourK = "4K"
        var id: String { rawValue }
    }

    enum UpscaleEngine: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case ai = "AI Super Resolution"
        var id: String { rawValue }
    }

    struct Info {
        let url: URL
        let name: String
        let duration: Double
        let fps: Double
        let width: Int
        let height: Int
        let bytes: Int64
        var durationText: String {
            let s = max(0, Int(duration.rounded()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { fps > 0 ? String(format: "%.1f FPS", fps) : "Unknown FPS" }
    }

    @Published var input: Info?
    @Published var output: Info?
    @Published var targetFPS = 60
    @Published var mode: Mode = .smooth
    @Published var quality: Quality = .twoK
    @Published var upscaleEngine: UpscaleEngine = .ai
    @Published var isProcessing = false
    @Published var stageText = ""
    @Published var progress: Double = 0
    @Published var errorText: String?
    @Published var showSaved = false
    @Published var noticeText: String?
    @Published var savedLibraryItem: LibraryStore.Item?

    let fpsOptions = [24, 30, 60, 120]

    func inspect(url: URL) async -> Info? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        do {
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let oriented = natural.applying(transform)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let fps = Double(try await track.load(.nominalFrameRate))
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return Info(url: url, name: url.lastPathComponent,
                        duration: duration.isFinite ? duration : 0,
                        fps: fps, width: max(2, Int(abs(oriented.width))),
                        height: max(2, Int(abs(oriented.height))), bytes: bytes)
        } catch { return nil }
    }

    func setInput(url: URL) async {
        errorText = nil
        noticeText = nil
        output = nil
        savedLibraryItem = nil
        progress = 0
        input = await inspect(url: url)
        if input == nil { errorText = "This video could not be opened. Try exporting it as MP4 or MOV first." }
    }

    private func even(_ v: Int) -> Int { max(2, v / 2 * 2) }

    private func outputSize(for source: Info) -> (Int, Int) {
        let targetLong: Int
        switch quality {
        case .enhanced: return (even(source.width), even(source.height))
        case .twoK: targetLong = 2560
        case .fourK: targetLong = 3840
        }
        let currentLong = max(source.width, source.height)
        if currentLong >= targetLong { return (even(source.width), even(source.height)) }
        let ratio = Double(targetLong) / Double(max(1, currentLong))
        return (even(Int(Double(source.width) * ratio)), even(Int(Double(source.height) * ratio)))
    }

    func convert(library: LibraryStore) async {
        guard let input else { return }
        isProcessing = true
        output = nil
        savedLibraryItem = nil
        errorText = nil
        noticeText = nil
        progress = 0.02
        defer { isProcessing = false }

        let temp = FileManager.default.temporaryDirectory
        let motionURL = temp.appendingPathComponent("motion_\(UUID().uuidString).mp4")
        let aiURLHolder = temp.appendingPathComponent("unused_\(UUID().uuidString).mov")
        let finalURL = temp.appendingPathComponent("ScreenFlow_\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: motionURL)
            try? FileManager.default.removeItem(at: aiURLHolder)
        }

        // Stage 1: create the requested frame rate while still at source resolution.
        stageText = mode == .smooth ? "Creating smooth motion" : "Converting frame rate"
        progress = 0.08
        let motionFilter = mode == .smooth
            ? "minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
            : "fps=\(targetFPS)"

        var motionArgs = ["ffmpeg", "-y", "-i", input.url.path,
                          "-map", "0:v:0", "-an", "-vf", motionFilter,
                          "-c:v", "h264_videotoolbox", "-b:v", "18000000",
                          "-pix_fmt", "yuv420p", motionURL.path]
        var motionCode = await runFFmpeg(motionArgs)

        // Some clips/codecs are happier when the hardware encoder receives HEVC.
        if motionCode != 0 {
            motionArgs = ["ffmpeg", "-y", "-i", input.url.path,
                          "-map", "0:v:0", "-an", "-vf", motionFilter,
                          "-c:v", "hevc_videotoolbox", "-b:v", "18000000",
                          "-pix_fmt", "yuv420p", motionURL.path]
            motionCode = await runFFmpeg(motionArgs)
        }
        guard motionCode == 0, FileManager.default.fileExists(atPath: motionURL.path) else {
            errorText = "Frame-rate conversion failed for this clip. Try Fast mode, or choose a lower FPS."
            return
        }
        progress = 0.34

        // Stage 2: AI SR is optional. If it cannot run on this device/clip, automatically fall back.
        var visualSource = motionURL
        var aiTemp: URL?
        if upscaleEngine == .ai && quality != .enhanced {
            stageText = "AI Super Resolution"
            do {
                let sr = AISuperResolution()
                let generated = try await sr.process(sourceURL: motionURL) { p in
                    Task { @MainActor in self.progress = 0.34 + p * 0.42 }
                }
                visualSource = generated
                aiTemp = generated
            } catch {
                noticeText = "AI Super Resolution was not available for this clip, so ScreenFlow automatically used the high-quality scaler instead."
                visualSource = motionURL
                progress = 0.76
            }
        } else {
            progress = 0.76
        }

        // Stage 3: final resolution + high quality hardware encode + original audio.
        stageText = "Finishing \(targetFPS) FPS · \(quality.rawValue)"
        let (outW, outH) = outputSize(for: input)
        var filters: [String] = []
        if upscaleEngine == .standard || visualSource == motionURL {
            filters.append("hqdn3d=0.55:0.55:2:2")
        }
        filters.append("scale=\(outW):\(outH):flags=lanczos")
        if upscaleEngine == .standard || visualSource == motionURL {
            filters.append("unsharp=5:5:0.22:5:5:0")
        }
        let vf = filters.joined(separator: ",")

        let pixels = Double(max(1, outW * outH))
        let fpsFactor = max(1.0, Double(targetFPS) / 30.0)
        let mbps = min(140.0, max(18.0, pixels / 2_073_600.0 * 20.0 * sqrt(fpsFactor)))
        let bitrate = String(Int(mbps * 1_000_000))
        let bufsize = String(Int(mbps * 2_000_000))
        let preferHEVC = quality == .fourK || targetFPS >= 120
        let firstCodec = preferHEVC ? "hevc_videotoolbox" : "h264_videotoolbox"
        let secondCodec = preferHEVC ? "h264_videotoolbox" : "hevc_videotoolbox"

        var finalCode = await encodeFinal(video: visualSource, original: input.url, output: finalURL,
                                          vf: vf, codec: firstCodec, bitrate: bitrate, bufsize: bufsize)
        if finalCode != 0 {
            finalCode = await encodeFinal(video: visualSource, original: input.url, output: finalURL,
                                          vf: vf, codec: secondCodec, bitrate: bitrate, bufsize: bufsize)
        }
        if let aiTemp { try? FileManager.default.removeItem(at: aiTemp) }

        guard finalCode == 0, FileManager.default.fileExists(atPath: finalURL.path),
              let finalInfo = await inspect(url: finalURL) else {
            errorText = "The final export could not be encoded on this iPhone. Try 4K/60, 2K/120, or Fast mode."
            return
        }

        progress = 0.96
        stageText = "Saving to ScreenFlow Library"
        do {
            let saved = try library.add(sourceURL: finalURL, info: finalInfo)
            savedLibraryItem = saved
            let permanentURL = library.url(for: saved)
            output = await inspect(url: permanentURL)
            try? FileManager.default.removeItem(at: finalURL)
        } catch {
            output = finalInfo
            noticeText = "Conversion finished, but the app could not copy it into the library. You can still share or save this result."
        }
        progress = 1
        stageText = "Done"
    }

    private func runFFmpeg(_ args: [String]) async -> Int {
        await Task.detached(priority: .userInitiated) { FFmpegSupport.ffmpeg(args) }.value
    }

    private func encodeFinal(video: URL, original: URL, output: URL, vf: String,
                             codec: String, bitrate: String, bufsize: String) async -> Int {
        try? FileManager.default.removeItem(at: output)
        let args = ["ffmpeg", "-y", "-i", video.path, "-i", original.path,
                    "-map", "0:v:0", "-map", "1:a?", "-vf", vf,
                    "-c:v", codec, "-b:v", bitrate, "-maxrate", bitrate,
                    "-bufsize", bufsize, "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "256k", "-shortest",
                    "-movflags", "+faststart", output.path]
        return await runFFmpeg(args)
    }

    func saveToPhotos() {
        guard let url = output?.url else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                Task { @MainActor in self.showSaved = success }
            }
        }
    }
}
