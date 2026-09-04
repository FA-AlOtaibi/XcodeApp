import AVFoundation
import Foundation
import Photos
import FFmpegSupport

@MainActor
final class VideoModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case simple = "Simple"
        case smooth = "Smooth"
        var id: String { rawValue }
    }

    enum Quality: String, CaseIterable, Identifiable {
        case enhanced = "Enhanced"
        case twoK = "2K"
        case fourK = "4K"
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
            let s = Int(duration.rounded())
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { fps > 0 ? String(format: "%.2f FPS", fps) : "Unknown FPS" }
    }

    @Published var input: Info?
    @Published var output: Info?
    @Published var targetFPS: Int = 60
    @Published var mode: Mode = .smooth
    @Published var quality: Quality = .twoK
    @Published var isProcessing = false
    @Published var stageText = ""
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
            return Info(url: url,
                        name: url.lastPathComponent,
                        duration: duration.isFinite ? duration : 0,
                        fps: fps,
                        width: Int(abs(oriented.width)),
                        height: Int(abs(oriented.height)),
                        bytes: bytes)
        } catch { return nil }
    }

    func setInput(url: URL) async {
        errorText = nil
        output = nil
        input = await inspect(url: url)
        if input == nil { errorText = "Could not read this video." }
    }

    private func even(_ value: Int) -> Int { max(2, value / 2 * 2) }

    private func outputSize(for input: Info) -> (Int, Int) {
        let longEdgeTarget: Int
        switch quality {
        case .enhanced:
            return (even(input.width), even(input.height))
        case .twoK:
            longEdgeTarget = 2560
        case .fourK:
            longEdgeTarget = 3840
        }

        let currentLong = max(input.width, input.height)
        if currentLong >= longEdgeTarget {
            return (even(input.width), even(input.height))
        }

        let ratio = Double(longEdgeTarget) / Double(max(1, currentLong))
        return (even(Int(Double(input.width) * ratio)), even(Int(Double(input.height) * ratio)))
    }

    func convert() async {
        guard let input else { return }
        isProcessing = true
        output = nil
        errorText = nil
        stageText = mode == .smooth ? "Analyzing motion and enhancing video…" : "Enhancing video and converting frame rate…"
        defer { isProcessing = false }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("FPS_\(targetFPS)_\(quality.rawValue)_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        let (outW, outH) = outputSize(for: input)

        var filters: [String] = []
        if mode == .simple {
            filters.append("fps=\(targetFPS)")
        } else {
            filters.append("minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1")
        }

        // Mild denoise keeps compression artifacts from being magnified by upscaling.
        filters.append("hqdn3d=1.1:1.1:5:5")

        if outW != input.width || outH != input.height {
            filters.append("scale=\(outW):\(outH):flags=lanczos")
        }

        // Conservative detail recovery; avoids the harsh halo look of aggressive sharpening.
        filters.append("unsharp=5:5:0.55:5:5:0.0")
        let videoFilter = filters.joined(separator: ",")

        let outputPixels = max(1, outW * outH)
        let fpsFactor = max(1.0, Double(targetFPS) / 30.0)
        let mbpsPer1080p30: Double
        switch quality {
        case .enhanced: mbpsPer1080p30 = 16.0
        case .twoK: mbpsPer1080p30 = 20.0
        case .fourK: mbpsPer1080p30 = 24.0
        }
        let baseMbps = max(12.0, min(95.0, Double(outputPixels) / 2_073_600.0 * mbpsPer1080p30 * sqrt(fpsFactor)))
        let bitrate = "\(Int(baseMbps * 1_000_000))"

        let args = [
            "ffmpeg", "-y", "-i", input.url.path,
            "-vf", videoFilter,
            "-c:v", "h264_videotoolbox",
            "-b:v", bitrate,
            "-maxrate", bitrate,
            "-bufsize", "\(Int(baseMbps * 2_000_000))",
            "-c:a", "aac", "-b:a", "256k",
            "-movflags", "+faststart",
            out.path
        ]

        stageText = "Creating \(targetFPS) FPS · \(quality.rawValue) output…"
        let code: Int = await Task.detached(priority: .userInitiated) { () -> Int in
            FFmpegSupport.ffmpeg(args)
        }.value

        guard code == 0, FileManager.default.fileExists(atPath: out.path) else {
            errorText = "Conversion failed. 4K + 120 FPS is extremely demanding; try 4K/60 or 2K/120 for this clip."
            return
        }
        stageText = "Finishing high-quality MP4…"
        output = await inspect(url: out)
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
