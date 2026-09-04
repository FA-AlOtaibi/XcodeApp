import AVFoundation
import Foundation
import FFmpegSupport

final class MotionInterpolator {
    enum MotionError: LocalizedError {
        case failed
        var errorDescription: String? { "Motion interpolation failed for this clip." }
    }

    func interpolate(sourceURL: URL,
                     targetFPS: Int,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = max(0.001, CMTimeGetSeconds(try await asset.load(.duration)))
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenFlow_motion_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        progress(0.02)

        let filter = "minterpolate=fps=\(targetFPS):mi_mode=mci:mc_mode=aobmc:me_mode=bidir:me=epzs:vsbmc=1"
        let args = [
            "ffmpeg", "-y", "-i", sourceURL.path,
            "-an",
            "-vf", filter,
            "-c:v", "h264_videotoolbox",
            "-b:v", "45000000",
            "-maxrate", "65000000",
            "-bufsize", "90000000",
            "-pix_fmt", "nv12",
            "-movflags", "+faststart",
            out.path
        ]

        let code: Int = await Task.detached(priority: .userInitiated) {
            FFmpegSupport.ffmpeg(args)
        }.value

        guard code == 0,
              FileManager.default.fileExists(atPath: out.path),
              ((try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value ?? 0) > 32_768 else {
            try? FileManager.default.removeItem(at: out)
            throw MotionError.failed
        }

        progress(min(1.0, duration / duration))
        return out
    }
}
