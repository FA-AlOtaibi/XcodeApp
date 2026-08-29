import SwiftUI
import AVKit
import AVFoundation
import Speech

@MainActor
final class PlaybackCenter: ObservableObject {
    static let shared = PlaybackCenter()

    @Published var item: LocalMedia?
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime = 0.0
    @Published var duration = 1.0
    @Published var expanded = false

    private var observer: Any?

    func play(_ media: LocalMedia) {
        guard media.isVideo || media.isAudio else { return }
        stop(removeItem: false)
        item = media
        let p = AVPlayer(url: media.url)
        p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player = p
        Task {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { }
            if let d = try? await AVURLAsset(url: media.url).load(.duration).seconds, d.isFinite, d > 0 {
                duration = d
            }
        }
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.35, preferredTimescale: 600), queue: .main) { [weak self, weak p] time in
            guard let self, let p else { return }
            self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            self.isPlaying = p.timeControlStatus == .playing
        }
        p.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause(); isPlaying = false
        } else {
            if currentTime >= duration - 0.15 { player.seek(to: .zero); currentTime = 0 }
            player.play(); isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let value = min(max(0, seconds), duration)
        currentTime = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(by seconds: Double) { seek(to: currentTime + seconds) }

    func stop(removeItem: Bool = true) {
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 1
        expanded = false
        if removeItem { item = nil }
    }
}

struct MiniPlaybackBar: View {
    @ObservedObject private var center = PlaybackCenter.shared

    var body: some View {
        if let item = center.item {
            HStack(spacing: 10) {
                Button { center.expanded = true } label: {
                    HStack(spacing: 10) {
                        LocalThumb(item: item)
                            .frame(width: 46, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.deletingPathExtension().lastPathComponent)
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            ProgressView(value: center.currentTime, total: max(1, center.duration))
                                .progressViewStyle(.linear)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button { center.seek(by: -10) } label: { Image(systemName: "gobackward.10") }
                Button { center.toggle() } label: {
                    Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
                Button { center.seek(by: 10) } label: { Image(systemName: "goforward.10") }
                Button { center.stop() } label: { Image(systemName: "xmark") }.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .sheet(isPresented: $center.expanded) { ExpandedPlaybackSheet() }
        }
    }
}

struct ExpandedPlaybackSheet: View {
    @ObservedObject private var center = PlaybackCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let item = center.item, let player = center.player {
                    Group {
                        if item.isVideo {
                            VideoPlayer(player: player)
                        } else {
                            ZStack {
                                Color.black
                                VStack(spacing: 14) {
                                    Image(systemName: "waveform.circle.fill").font(.system(size: 78))
                                    Text(item.url.deletingPathExtension().lastPathComponent).lineLimit(2)
                                }.foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    Slider(value: Binding(get: { center.currentTime }, set: { center.seek(to: $0) }), in: 0...max(1, center.duration))

                    HStack(spacing: 34) {
                        Button { center.seek(by: -10) } label: { Image(systemName: "gobackward.10").font(.title2) }
                        Button { center.toggle() } label: {
                            Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2).frame(width: 54, height: 54).background(.thinMaterial, in: Circle())
                        }
                        Button { center.seek(by: 10) } label: { Image(systemName: "goforward.10").font(.title2) }
                    }
                    Spacer()
                }
            }
            .padding(18)
            .navigationTitle("التشغيل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { center.expanded = false; dismiss() } label: { Label("تصغير", systemImage: "chevron.down") }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

extension AppModel {
    func translateVideoToSRTFixed(_ item: LocalMedia, targetLanguage: String) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        do {
            let auth = await requestSpeechAuthorizationFixed()
            guard auth == .authorized else { throw AppError.message("يلزم السماح بالتعرف على الكلام من الإعدادات") }

            let speechURL = try await makeSpeechInputFixed(item)
            defer { if speechURL != item.url { try? FileManager.default.removeItem(at: speechURL) } }

            let locales = [Locale(identifier: "ar-SA"), Locale(identifier: "en-US")]
            var best: SFSpeechRecognitionResult?
            for locale in locales {
                if let result = try? await recognizeSpeechFixed(speechURL, locale: locale),
                   result.bestTranscription.formattedString.count > (best?.bestTranscription.formattedString.count ?? 0) {
                    best = result
                }
            }
            guard let result = best, !result.bestTranscription.segments.isEmpty else {
                throw AppError.message("لم أتمكن من التعرف على الكلام في هذا المقطع")
            }

            let groups = makeSubtitleGroupsFixed(result.bestTranscription.segments)
            var srt = ""
            for (idx, group) in groups.enumerated() {
                let translated = try await translateTextFixed(group.text, target: targetLanguage)
                srt += "\(idx + 1)\n\(srtTimeFixed(group.start)) --> \(srtTimeFixed(group.end))\n\(translated)\n\n"
            }
            let suffix = targetLanguage == "ar" ? "ar" : "en"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix).srt")
            try srt.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم إنشاء ملف الترجمة SRT", .success)
        } catch {
            show(readable(error), .error)
        }
    }

    private func requestSpeechAuthorizationFixed() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func makeSpeechInputFixed(_ item: LocalMedia) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else { throw AppError.message("الفيديو لا يحتوي على صوت") }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز صوت الفيديو") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a")
        export.outputURL = tmp; export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر استخراج الصوت للترجمة") }
        return tmp
    }

    private func recognizeSpeechFixed(_ url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw AppError.message("خدمة التعرف على الكلام غير متاحة الآن") }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal, !finished {
                    finished = true; continuation.resume(returning: result)
                } else if let error, !finished {
                    finished = true; continuation.resume(throwing: error)
                }
            }
            _ = task
        }
    }

    private struct SubtitleGroupFixed { let start: Double; let end: Double; let text: String }
    private func makeSubtitleGroupsFixed(_ segments: [SFTranscriptionSegment]) -> [SubtitleGroupFixed] {
        var output: [SubtitleGroupFixed] = []
        var words: [String] = []; var start = 0.0; var end = 0.0
        for seg in segments {
            if words.isEmpty { start = seg.timestamp }
            words.append(seg.substring); end = seg.timestamp + seg.duration
            if words.count >= 9 || end - start >= 3.8 {
                output.append(.init(start: start, end: max(end, start + 0.35), text: words.joined(separator: " ")))
                words.removeAll(keepingCapacity: true)
            }
        }
        if !words.isEmpty { output.append(.init(start: start, end: max(end, start + 0.35), text: words.joined(separator: " "))) }
        return output
    }

    private func translateTextFixed(_ text: String, target: String) async throws -> String {
        guard var parts = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else { return text }
        parts.queryItems = [
            .init(name: "client", value: "gtx"), .init(name: "sl", value: "auto"),
            .init(name: "tl", value: target), .init(name: "dt", value: "t"), .init(name: "q", value: text)
        ]
        guard let url = parts.url else { return text }
        var req = URLRequest(url: url); req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let rows = root.first as? [Any] else { throw AppError.message("تعذر الاتصال بخدمة الترجمة") }
        let translated = rows.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return translated.isEmpty ? text : translated
    }

    private func srtTimeFixed(_ seconds: Double) -> String {
        let ms = max(0, Int(seconds * 1000))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    func separateCenterAudioFixed(from item: LocalMedia, keepVoice: Bool) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else { throw AppError.message("الفيديو لا يحتوي على صوت") }

            let sourceAudio = FileManager.default.temporaryDirectory.appendingPathComponent("source-\(UUID().uuidString).m4a")
            let processed = FileManager.default.temporaryDirectory.appendingPathComponent("processed-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: sourceAudio); try? FileManager.default.removeItem(at: processed) }

            guard let exportAudio = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز الصوت") }
            exportAudio.outputURL = sourceAudio; exportAudio.outputFileType = .m4a
            await exportAudio.export()
            guard exportAudio.status == .completed else { throw exportAudio.error ?? AppError.message("تعذر استخراج الصوت") }

            let input = try AVAudioFile(forReading: sourceAudio)
            let format = input.processingFormat
            guard format.channelCount >= 2 else { throw AppError.message("هذه الميزة تحتاج صوت ستيريو") }
            let output = try AVAudioFile(forWriting: processed, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw AppError.message("تعذر تجهيز معالجة الصوت") }

            while true {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                guard let channels = buffer.floatChannelData else { throw AppError.message("صيغة الصوت غير مدعومة") }
                let frames = Int(buffer.frameLength)
                let left = channels[0], right = channels[1]
                for i in 0..<frames {
                    let l = left[i], r = right[i]
                    if keepVoice {
                        let mid = max(-1, min(1, (l + r) * 0.5))
                        left[i] = mid; right[i] = mid
                    } else {
                        let side = max(-1, min(1, (l - r) * 0.5))
                        left[i] = side; right[i] = -side
                    }
                }
                try output.write(from: buffer)
                buffer.frameLength = 0
            }

            let processedAsset = AVURLAsset(url: processed)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
                  let processedAudio = try await processedAsset.loadTracks(withMediaType: .audio).first else { throw AppError.message("تعذر تجهيز النتيجة") }
            let composition = AVMutableComposition()
            let duration = try await asset.load(.duration)
            guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر تجهيز الفيديو") }
            try v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
            v.preferredTransform = try await sourceVideo.load(.preferredTransform)
            let audioDuration = try await processedAsset.load(.duration)
            try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: processedAudio, at: .zero)

            let suffix = keepVoice ? "voice" : "no-voice"
            let result = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix).mp4")
            try? FileManager.default.removeItem(at: result)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز التصدير") }
            export.outputURL = result; export.outputFileType = .mp4
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل إنشاء النتيجة") }
            _ = try persist(result, result.lastPathComponent)
            refreshStorage()
            show(keepVoice ? "تم إنشاء نسخة تقلل الموسيقى وتبرز الكلام" : "تم إنشاء نسخة تقلل الصوت البشري", .success)
        } catch {
            show(readable(error), .error)
        }
    }
}
