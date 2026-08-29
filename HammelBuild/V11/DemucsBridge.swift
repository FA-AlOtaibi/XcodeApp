import Foundation
import AVFoundation

extension AppModel {
    func separateWithDemucs(from item: LocalMedia, keepVoice: Bool) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        show(keepVoice ? "جارٍ عزل الصوت البشري بالذكاء الاصطناعي…" : "جارٍ حذف الصوت البشري وإبقاء الموسيقى…", .info)
        do {
            let sourceAudio = try await demucsAudioSource(from: item)
            defer { if sourceAudio != item.url { try? FileManager.default.removeItem(at: sourceAudio) } }

            let vm = DemucsViewModel()
            vm.audioURL = sourceAudio
            try await vm.performSeparation(mode: .full)

            guard let vocals = vm.stemURLs[.vocals] else {
                throw AppError.message("لم يتم إنشاء مسار الصوت البشري")
            }

            let selectedAudio: URL
            var mixedMusic: URL?
            if keepVoice {
                selectedAudio = vocals
            } else {
                let needed: [Stem] = [.drums, .bass, .other]
                let urls = needed.compactMap { vm.stemURLs[$0] }
                guard urls.count == needed.count else { throw AppError.message("تعذر إنشاء مسار الموسيقى") }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demucs-music-\(UUID().uuidString).wav")
                try mixDemucsStems(urls, to: tmp)
                mixedMusic = tmp
                selectedAudio = tmp
            }
            defer { if let mixedMusic { try? FileManager.default.removeItem(at: mixedMusic) } }

            if item.isVideo {
                let suffix = keepVoice ? "vocals" : "music"
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix)-AI.mp4")
                try? FileManager.default.removeItem(at: out)
                try await remuxVideo(item.url, audioURL: selectedAudio, output: out)
                _ = try persist(out, out.lastPathComponent)
            } else {
                let suffix = keepVoice ? "vocals" : "music"
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix)-AI.wav")
                try? FileManager.default.removeItem(at: out)
                try FileManager.default.copyItem(at: selectedAudio, to: out)
                _ = try persist(out, out.lastPathComponent)
            }

            refreshStorage()
            show(keepVoice ? "تم عزل الكلام وحذف الموسيقى بالـAI" : "تم حذف الكلام وإبقاء الموسيقى بالـAI", .success)
        } catch {
            show(readable(error), .error)
        }
    }

    private func demucsAudioSource(from item: LocalMedia) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else {
            throw AppError.message("الفيديو لا يحتوي على صوت")
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("تعذر تجهيز صوت الفيديو")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demucs-source-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: tmp)
        export.outputURL = tmp
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر استخراج صوت الفيديو") }
        return tmp
    }

    private func mixDemucsStems(_ urls: [URL], to outputURL: URL) throws {
        let files = try urls.map { try AVAudioFile(forReading: $0) }
        guard let first = files.first else { throw AppError.message("لا توجد مسارات صوت") }
        let format = first.processingFormat
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAudioFile(forWriting: outputURL, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let capacity: AVAudioFrameCount = 8192

        while true {
            var buffers: [AVAudioPCMBuffer] = []
            var maxFrames: AVAudioFrameCount = 0
            for file in files {
                guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AppError.message("تعذر تجهيز الصوت") }
                try file.read(into: b, frameCount: capacity)
                maxFrames = max(maxFrames, b.frameLength)
                buffers.append(b)
            }
            if maxFrames == 0 { break }
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames), let outData = out.floatChannelData else {
                throw AppError.message("تعذر مزج الموسيقى")
            }
            out.frameLength = maxFrames
            let channelCount = Int(format.channelCount)
            for ch in 0..<channelCount {
                for frame in 0..<Int(maxFrames) {
                    var value: Float = 0
                    for b in buffers where frame < Int(b.frameLength) {
                        if let d = b.floatChannelData { value += d[ch][frame] }
                    }
                    outData[ch][frame] = min(1, max(-1, value))
                }
            }
            try writer.write(from: out)
        }
    }

    private func remuxVideo(_ videoURL: URL, audioURL: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw AppError.message("تعذر تجهيز الفيديو الناتج")
        }
        let composition = AVMutableComposition()
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)
        guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.message("تعذر تجهيز المسارات")
        }
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        v.preferredTransform = try await sourceVideo.load(.preferredTransform)
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudio, at: .zero)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw AppError.message("تعذر تجهيز التصدير")
        }
        export.outputURL = output
        export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("فشل إنشاء الفيديو بعد فصل الصوت") }
    }
}
