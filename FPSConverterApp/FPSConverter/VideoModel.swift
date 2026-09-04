import AVFoundation
import Foundation
import Photos
import FFmpegSupport

@MainActor
final class VideoModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable { case simple = "Fast", smooth = "Smooth"; var id: String { rawValue } }
    enum Quality: String, CaseIterable, Identifiable { case enhanced = "Enhanced", twoK = "2K", fourK = "4K"; var id: String { rawValue } }
    enum UpscaleEngine: String, CaseIterable, Identifiable { case standard = "Standard", ai = "AI Super Resolution"; var id: String { rawValue } }

    struct Info {
        let url: URL
        let name: String
        let duration: Double
        let fps: Double
        let width: Int
        let height: Int
        let bytes: Int64
        var durationText: String { let s = max(0, Int(duration.rounded())); return String(format: "%d:%02d", s / 60, s % 60) }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { fps > 0 ? String(format: "%.1f FPS", fps) : "Unknown FPS" }
    }

    @Published var input: Info?
    @Published var output: Info?
    @Published var targetFPS = 60
    @Published var mode: Mode = .smooth
    @Published var quality: Quality = .twoK
    @Published var upscaleEngine: UpscaleEngine = .standard
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
            return Info(url: url, name: url.lastPathComponent, duration: duration.isFinite ? duration : 0,
                        fps: fps, width: max(2, Int(abs(oriented.width))), height: max(2, Int(abs(oriented.height))), bytes: bytes)
        } catch { return nil }
    }

    func setInput(url: URL) async {
        errorText = nil; noticeText = nil; output = nil; savedLibraryItem = nil; progress = 0
        input = await inspect(url: url)
        if input == nil { errorText = "This video could not be opened. Try MP4 or MOV." }
    }

    func clearInput() {
        input = nil; output = nil; savedLibraryItem = nil; progress = 0; errorText = nil; noticeText = nil
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
        isProcessing = true; output = nil; savedLibraryItem = nil; errorText = nil; noticeText = nil; progress = 0.02
        defer { isProcessing = false }

        let temp = FileManager.default.temporaryDirectory
        let motionURL = temp.appendingPathComponent("motion_\(UUID().uuidString).mp4")
        let finalURL = temp.appendingPathComponent("ScreenFlow_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: motionURL); try? FileManager.default.removeItem(at: finalURL) }

        // Stage 1: frame-rate conversion at source resolution. Keep this separate from 2K/4K scaling.
        stageText = mode == .smooth ? "Creating smooth motion" : "Converting frame rate"
        progress = 0.08
        let motionFilter = mode == .smooth
            ? "minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
            : "fps=\(targetFPS)"

        let motionEncoders: [[String]] = [
            ["-c:v", "h264_videotoolbox", "-b:v", motionBitrate(input), "-pix_fmt", "yuv420p"],
            ["-c:v", "hevc_videotoolbox", "-b:v", motionBitrate(input), "-pix_fmt", "yuv420p", "-tag:v", "hvc1"],
            ["-c:v", "mpeg4", "-q:v", "2"]
        ]

        var motionOK = false
        for encoder in motionEncoders {
            try? FileManager.default.removeItem(at: motionURL)
            var args = ["ffmpeg", "-y", "-i", input.url.path, "-map", "0:v:0", "-an", "-vf", motionFilter]
            args.append(contentsOf: encoder)
            args.append(contentsOf: ["-r", "\(targetFPS)", motionURL.path])
            let code = await runFFmpeg(args)
            if code == 0, FileManager.default.fileExists(atPath: motionURL.path) { motionOK = true; break }
        }
        guard motionOK else {
            errorText = "Could not create the requested frame rate for this clip. Try Fast mode or 60 FPS."
            return
        }
        progress = 0.34

        // Stage 2: optional AI SR. Never fail the whole conversion just because AI is unavailable.
        var visualSource = motionURL
        var aiTemp: URL?
        if upscaleEngine == .ai && quality != .enhanced {
            stageText = "AI Super Resolution"
            do {
                let generated = try await AISuperResolution().process(sourceURL: motionURL) { p in
                    Task { @MainActor in self.progress = 0.34 + p * 0.38 }
                }
                visualSource = generated
                aiTemp = generated
            } catch {
                noticeText = "AI Super Resolution was unavailable for this clip, so ScreenFlow continued with Standard high-quality scaling."
                visualSource = motionURL
            }
        }
        progress = max(progress, 0.72)

        // Stage 3: final scaling + encode. Try hardware codecs first, then a universal software fallback.
        stageText = "Upscaling and encoding"
        let (outW, outH) = outputSize(for: input)
        var filters: [String] = []
        if visualSource == motionURL { filters.append("hqdn3d=0.45:0.45:1.5:1.5") }
        filters.append("scale=\(outW):\(outH):flags=lanczos")
        if visualSource == motionURL { filters.append("unsharp=5:5:0.18:5:5:0") }
        let vf = filters.joined(separator: ",")
        let bitrate = exportBitrate(width: outW, height: outH)

        let encoders: [[String]] = [
            ["-c:v", "hevc_videotoolbox", "-b:v", bitrate, "-pix_fmt", "yuv420p", "-tag:v", "hvc1"],
            ["-c:v", "h264_videotoolbox", "-b:v", bitrate, "-pix_fmt", "yuv420p"],
            ["-c:v", "mpeg4", "-q:v", "2"]
        ]

        var finalOK = false
        for encoder in encoders {
            try? FileManager.default.removeItem(at: finalURL)
            var args = ["ffmpeg", "-y", "-i", visualSource.path, "-i", input.url.path,
                        "-map", "0:v:0", "-map", "1:a?", "-vf", vf]
            args.append(contentsOf: encoder)
            args.append(contentsOf: ["-r", "\(targetFPS)", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", finalURL.path])
            let code = await runFFmpeg(args)
            if code == 0, FileManager.default.fileExists(atPath: finalURL.path) { finalOK = true; break }
        }
        if let aiTemp { try? FileManager.default.removeItem(at: aiTemp) }

        guard finalOK, let finalInfo = await inspect(url: finalURL) else {
            errorText = "The clip was processed, but the final file could not be encoded. Try Enhanced quality for this video."
            return
        }

        progress = 0.94
        stageText = "Saving to Library"
        do {
            let saved = try library.add(sourceURL: finalURL, info: finalInfo)
            savedLibraryItem = saved
            output = await inspect(url: library.url(for: saved))
        } catch {
            output = finalInfo
            noticeText = "The video finished, but could not be copied into the in-app Library. You can still save or share it now."
        }
        progress = 1
        stageText = "Done"
    }

    private func runFFmpeg(_ args: [String]) async -> Int {
        await Task.detached(priority: .userInitiated) { FFmpegSupport.ffmpeg(args) }.value
    }

    private func motionBitrate(_ input: Info) -> String {
        let pixels = Double(max(1, input.width * input.height))
        let factor = max(1.0, Double(targetFPS) / max(24.0, input.fps > 0 ? input.fps : 30.0))
        let mbps = min(70.0, max(10.0, pixels / 2_073_600.0 * 14.0 * sqrt(factor)))
        return String(Int(mbps * 1_000_000))
    }

    private func exportBitrate(width: Int, height: Int) -> String {
        let pixels = Double(max(1, width * height))
        let fpsFactor = max(1.0, Double(targetFPS) / 30.0)
        let mbps = min(120.0, max(16.0, pixels / 2_073_600.0 * 18.0 * sqrt(fpsFactor)))
        return String(Int(mbps * 1_000_000))
    }

    func saveToPhotos() {
        guard let url = output?.url else { return }
        saveURLToPhotos(url)
    }

    func saveURLToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in Task { @MainActor in self.showSaved = success } }
        }
    }
}
