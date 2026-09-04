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
        var durationText: String { let s = Int(duration.rounded()); return String(format: "%d:%02d", s / 60, s % 60) }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { fps > 0 ? String(format: "%.2f FPS", fps) : "Unknown FPS" }
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
                        fps: fps, width: Int(abs(oriented.width)), height: Int(abs(oriented.height)), bytes: bytes)
        } catch { return nil }
    }

    func setInput(url: URL) async {
        errorText = nil; output = nil; progress = 0
        input = await inspect(url: url)
        if input == nil { errorText = "Could not read this video." }
    }

    private func even(_ v: Int) -> Int { max(2, v / 2 * 2) }

    private func outputSize(for input: Info) -> (Int, Int) {
        let target: Int
        switch quality {
        case .enhanced: return (even(input.width), even(input.height))
        case .twoK: target = 2560
        case .fourK: target = 3840
        }
        let currentLong = max(input.width, input.height)
        if currentLong >= target { return (even(input.width), even(input.height)) }
        let ratio = Double(target) / Double(max(1, currentLong))
        return (even(Int(Double(input.width) * ratio)), even(Int(Double(input.height) * ratio)))
    }

    func convert() async {
        guard let input else { return }
        isProcessing = true; output = nil; errorText = nil; progress = 0
        defer { isProcessing = false }

        let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("FPS_Quality_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: finalURL)
        var videoSource = input.url
        var aiTemp: URL?

        if upscaleEngine == .ai {
            stageText = "AI Super Resolution · Apple Neural Engine"
            do {
                let sr = AISuperResolution()
                let temp = try await sr.process(sourceURL: input.url) { p in
                    Task { @MainActor in self.progress = p * 0.72 }
                }
                videoSource = temp
                aiTemp = temp
            } catch {
                errorText = "AI Super Resolution could not process this clip. Try Standard mode for this video."
                return
            }
        }

        let (outW, outH) = outputSize(for: input)
        var filters: [String] = []
        filters.append(mode == .smooth
            ? "minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
            : "fps=\(targetFPS)")

        if upscaleEngine == .standard {
            filters.append("hqdn3d=0.8:0.8:3:3")
        }
        filters.append("scale=\(outW):\(outH):flags=lanczos")
        if upscaleEngine == .standard { filters.append("unsharp=5:5:0.35:5:5:0") }
        let vf = filters.joined(separator: ",")

        let outputPixels = max(1, outW * outH)
        let fpsFactor = max(1.0, Double(targetFPS) / 30.0)
        let base = quality == .fourK ? 26.0 : (quality == .twoK ? 21.0 : 17.0)
        let mbps = max(14.0, min(110.0, Double(outputPixels) / 2_073_600.0 * base * sqrt(fpsFactor)))
        let bitrate = "\(Int(mbps * 1_000_000))"

        stageText = "Creating \(targetFPS) FPS · \(quality.rawValue)"
        progress = max(progress, 0.74)
        let args = [
            "ffmpeg", "-y", "-i", videoSource.path, "-i", input.url.path,
            "-map", "0:v:0", "-map", "1:a?", "-vf", vf,
            "-c:v", "h264_videotoolbox", "-b:v", bitrate, "-maxrate", bitrate,
            "-bufsize", "\(Int(mbps * 2_000_000))", "-c:a", "aac", "-b:a", "256k",
            "-movflags", "+faststart", finalURL.path
        ]

        let code: Int = await Task.detached(priority: .userInitiated) { FFmpegSupport.ffmpeg(args) }.value
        if let aiTemp { try? FileManager.default.removeItem(at: aiTemp) }
        guard code == 0, FileManager.default.fileExists(atPath: finalURL.path) else {
            errorText = "Conversion failed. 4K + 120 FPS is very demanding; try 4K/60 or 2K/120."
            return
        }
        progress = 1
        stageText = "Done"
        output = await inspect(url: finalURL)
    }

    func saveToPhotos() {
        guard let url = output?.url else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in Task { @MainActor in self.showSaved = success } }
        }
    }
}
