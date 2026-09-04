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

    func convert() async {
        guard let input else { return }
        isProcessing = true
        output = nil
        errorText = nil
        stageText = mode == .smooth ? "Analyzing motion and creating in-between frames…" : "Converting frame rate…"
        defer { isProcessing = false }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("FPS_\(targetFPS)_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        let videoFilter: String
        switch mode {
        case .simple:
            videoFilter = "fps=\(targetFPS)"
        case .smooth:
            videoFilter = "minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
        }

        let pixelCount = max(1, input.width * input.height)
        let baseMbps = max(8.0, min(45.0, Double(pixelCount) / 2_073_600.0 * (targetFPS >= 60 ? 20.0 : 14.0)))
        let bitrate = "\(Int(baseMbps * 1_000_000))"

        let args = [
            "ffmpeg", "-y", "-i", input.url.path,
            "-vf", videoFilter,
            "-c:v", "h264_videotoolbox",
            "-b:v", bitrate,
            "-maxrate", bitrate,
            "-bufsize", "\(Int(baseMbps * 2_000_000))",
            "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart",
            out.path
        ]

        stageText = mode == .smooth ? "Smooth conversion in progress…" : "Fast conversion in progress…"
        let code: Int32 = await Task.detached(priority: .userInitiated) {
            ffmpeg(args)
        }.value

        guard code == 0, FileManager.default.fileExists(atPath: out.path) else {
            errorText = mode == .smooth
                ? "Smooth conversion failed on this clip. Try Simple mode or a shorter video."
                : "Conversion failed for this video."
            return
        }
        stageText = "Finishing MP4…"
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
