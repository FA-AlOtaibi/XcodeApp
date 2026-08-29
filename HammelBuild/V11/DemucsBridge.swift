import Foundation
import AVFoundation

extension AppModel {
    func separateWithDemucs(from item: LocalMedia, keepVoice: Bool) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        show(keepVoice ? "جارٍ عزل الكلام…" : "جارٍ فصل الموسيقى…", .info)
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
                guard urls.count == needed.count else { throw AppError.message("تعذر إنشاء مسارات الموسيقى") }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demucs-music-\(UUID().uuidString).m4a")
                try await mixDemucsStems(urls, to: tmp)
                mixedMusic = tmp
                selectedAudio = tmp
            }
            defer { if let mixedMusic { try? FileManager.default.removeItem(at: mixedMusic) } }

            if item.isVideo {
                let suffix = keepVoice ? "voice" : "music"
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix).mp4")
                try? FileManager.default.removeItem(at: out)
                try await remuxVideo(item.url, audioURL: selectedAudio, output: out)
                _ = try persist(out, out.lastPathComponent)
            } else {
                let suffix = keepVoice ? "voice" : "music"
                let ext = selectedAudio.pathExtension.isEmpty ? "wav" : selectedAudio.pathExtension
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix).\(ext)")
                try? FileManager.default.removeItem(at: out)
                try FileManager.default.copyItem(at: selectedAudio, to: out)
                _ = try persist(out, out.lastPathComponent)
            }

            refreshStorage()
            show(keepVoice ? "تم إبقاء الكلام وحذف الموسيقى" : "تم إبقاء الموسيقى وحذف الكلام", .success)
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

    private func mixDemucsStems(_ urls: [URL], to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        var params: [AVAudioMixInputParameters] = []
        var longest = CMTime.zero

        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw AppError.message("أحد مسارات الموسيقى غير صالح")
            }
            let duration = try await asset.load(.duration)
            longest = CMTimeMaximum(longest, duration)
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw AppError.message("تعذر تجهيز مسار الموسيقى")
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(1.0, at: .zero)
            params.append(p)
        }

        guard longest > .zero else { throw AppError.message("مسارات الموسيقى فارغة") }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("تعذر تجهيز الموسيقى الناتجة")
        }
        exporter.audioMix = mix
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? AppError.message("فشل دمج مسارات الموسيقى")
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
