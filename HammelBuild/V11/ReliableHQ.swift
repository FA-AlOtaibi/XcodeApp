import Foundation
import AVFoundation

extension AppModel {
    func muxHQReliableV32(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)

        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw AppError.message("تعذر قراءة فيديو الجودة العالية")
        }
        guard let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw AppError.message("تعذر قراءة صوت الجودة العالية")
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.message("تعذر تجهيز الدمج")
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudio, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        try? FileManager.default.removeItem(at: output)

        let natural = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform).standardized
        let maxDimension = max(abs(rect.width), abs(rect.height))

        let compatible = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let candidates: [String]
        if maxDimension >= 3000 {
            candidates = [AVAssetExportPreset3840x2160, AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality]
        } else if maxDimension >= 1500 {
            candidates = [AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality, AVAssetExportPreset1280x720]
        } else {
            candidates = [AVAssetExportPreset1280x720, AVAssetExportPresetHighestQuality]
        }

        var lastError: Error?
        for preset in candidates where compatible.contains(preset) {
            try? FileManager.default.removeItem(at: output)
            guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            exporter.outputURL = output
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = false
            await exporter.export()
            if exporter.status == .completed, FileManager.default.fileExists(atPath: output.path) {
                return
            }
            lastError = exporter.error
        }

        throw lastError ?? AppError.message("فشل دمج الفيديو والصوت")
    }
}
