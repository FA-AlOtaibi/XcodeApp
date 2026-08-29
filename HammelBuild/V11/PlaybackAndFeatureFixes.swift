import SwiftUI
import AVKit
import AVFoundation
import Speech
import MediaPlayer

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
    private var remoteConfigured = false

    func play(_ media: LocalMedia) {
        guard media.isVideo || media.isAudio else { return }
        if item?.url == media.url, let player {
            player.play(); isPlaying = true; updateNowPlaying(); return
        }

        stop(removeItem: false)
        item = media
        currentTime = 0
        duration = 1

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch { }

        let p = AVPlayer(url: media.url)
        p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player = p
        configureRemoteCommands()

        Task {
            if let d = try? await AVURLAsset(url: media.url).load(.duration).seconds, d.isFinite, d > 0 {
                duration = d
                updateNowPlaying()
            }
        }

        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak p] time in
            guard let self, let p else { return }
            self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            self.isPlaying = p.timeControlStatus == .playing
            self.updateNowPlaying()
        }

        p.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause(); isPlaying = false
        } else {
            if currentTime >= duration - 0.15 { player.seek(to: .zero); currentTime = 0 }
            player.play(); isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let value = min(max(0, seconds), max(0, duration))
        currentTime = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if removeItem { item = nil }
    }

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.play(); self?.isPlaying = true; self?.updateNowPlaying() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.pause(); self?.isPlaying = false; self?.updateNowPlaying() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: 10) }; return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: -10) }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let item else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.url.deletingPathExtension().lastPathComponent,
            MPMediaItemPropertyPlaybackDuration: max(0, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, currentTime),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}

struct MiniPlaybackBar: View {
    @ObservedObject private var center = PlaybackCenter.shared

    var body: some View {
        if let item = center.item {
            VStack(spacing: 0) {
                ProgressView(value: center.currentTime, total: max(1, center.duration))
                    .tint(.primary.opacity(0.72))
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    Button { center.expanded = true } label: {
                        HStack(spacing: 10) {
                            LocalThumb(item: item)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url.deletingPathExtension().lastPathComponent)
                                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(clock(center.currentTime))  •  \(clock(center.duration))")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 2)
                    Button { center.seek(by: -10) } label: { Image(systemName: "gobackward.10") }
                    Button { center.toggle() } label: {
                        Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(.primary.opacity(0.10), in: Circle())
                    }
                    Button { center.seek(by: 10) } label: { Image(systemName: "goforward.10") }
                    Button { center.stop() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.24), radius: 20, y: 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .fullScreenCover(isPresented: $center.expanded) { FullScreenPlaybackView() }
        }
    }

    private func clock(_ s: Double) -> String {
        let v = max(0, Int(s.isFinite ? s : 0))
        if v >= 3600 { return String(format: "%d:%02d:%02d", v/3600, (v%3600)/60, v%60) }
        return String(format: "%02d:%02d", v/60, v%60)
    }
}

struct FullScreenPlaybackView: View {
    @ObservedObject private var center = PlaybackCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = center.item, let player = center.player {
                if item.isVideo {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ZStack {
                        LinearGradient(colors: [.black, .gray.opacity(0.30), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                        VStack(spacing: 18) {
                            LocalThumb(item: item)
                                .frame(width: 250, height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            Text(item.url.deletingPathExtension().lastPathComponent)
                                .font(.title2.bold()).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                        }.padding(30)
                    }
                }

                VStack {
                    HStack {
                        Button { center.expanded = false; dismiss() } label: {
                            Image(systemName: "chevron.down")
                                .font(.headline.bold()).frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                        Text(item.url.deletingPathExtension().lastPathComponent)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16).padding(.top, 8)

                    Spacer()

                    VStack(spacing: 12) {
                        Slider(value: Binding(get: { center.currentTime }, set: { center.seek(to: $0) }), in: 0...max(1, center.duration))
                            .tint(.white)
                        HStack {
                            Text(clock(center.currentTime))
                            Spacer()
                            Text("-\(clock(max(0, center.duration-center.currentTime)))")
                        }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.72))
                        HStack(spacing: 42) {
                            Button { center.seek(by: -10) } label: { Image(systemName: "gobackward.10").font(.title) }
                            Button { center.toggle() } label: {
                                Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2.bold()).frame(width: 62, height: 62)
                                    .background(.white, in: Circle()).foregroundStyle(.black)
                            }
                            Button { center.seek(by: 10) } label: { Image(systemName: "goforward.10").font(.title) }
                        }.foregroundStyle(.white)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.horizontal, 16).padding(.bottom, 18)
                }
            }
        }
    }

    private func clock(_ s: Double) -> String {
        let v = max(0, Int(s.isFinite ? s : 0))
        if v >= 3600 { return String(format: "%d:%02d:%02d", v/3600, (v%3600)/60, v%60) }
        return String(format: "%02d:%02d", v/60, v%60)
    }
}

extension AppModel {
    func translateVideoToSRTFixed(_ item: LocalMedia, targetLanguage: String) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        do {
            let auth = await requestSpeechAuthorizationFixed()
            guard auth == .authorized else { throw AppError.message("اسمح بالتعرف على الكلام من إعدادات iOS") }
            let speechURL = try await makeSpeechInputFixed(item)
            defer { if speechURL != item.url { try? FileManager.default.removeItem(at: speechURL) } }

            let locales = [Locale(identifier: "ar-SA"), Locale(identifier: "en-US"), Locale(identifier: "en-GB")]
            var best: SFSpeechRecognitionResult?
            var lastError: Error?
            for locale in locales {
                do {
                    let result = try await recognizeSpeechFixed(speechURL, locale: locale)
                    if result.bestTranscription.formattedString.count > (best?.bestTranscription.formattedString.count ?? 0) { best = result }
                } catch { lastError = error }
            }
            guard let result = best, !result.bestTranscription.segments.isEmpty else {
                throw lastError ?? AppError.message("لم أتمكن من التعرف على الكلام في هذا المقطع")
            }

            let groups = makeSubtitleGroupsFixed(result.bestTranscription.segments)
            var srt = ""
            for (idx, group) in groups.enumerated() {
                let translated = try await translateTextFixed(group.text, target: targetLanguage)
                srt += "\(idx + 1)\n\(srtTimeFixed(group.start)) --> \(srtTimeFixed(group.end))\n\(translated)\n\n"
            }
            let suffix = targetLanguage == "ar" ? "ar" : "en"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-translated-\(suffix).srt")
            try? FileManager.default.removeItem(at: tmp)
            try srt.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم إنشاء الترجمة", .success)
        } catch { show(readable(error), .error) }
    }

    private func requestSpeechAuthorizationFixed() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
    }

    private func makeSpeechInputFixed(_ item: LocalMedia) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else { throw AppError.message("الفيديو لا يحتوي على صوت") }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز صوت الفيديو") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: tmp)
        export.outputURL = tmp; export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر استخراج الصوت للترجمة") }
        return tmp
    }

    private func recognizeSpeechFixed(_ url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw AppError.message("التعرف على الكلام غير متاح الآن") }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal, !finished { finished = true; continuation.resume(returning: result) }
                else if let error, !finished { finished = true; continuation.resume(throwing: error) }
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
        parts.queryItems = [.init(name:"client",value:"gtx"),.init(name:"sl",value:"auto"),.init(name:"tl",value:target),.init(name:"dt",value:"t"),.init(name:"q",value:text)]
        guard let url = parts.url else { return text }
        var req = URLRequest(url: url); req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [Any], let rows = root.first as? [Any] else {
            throw AppError.message("تعذر ترجمة النص الآن")
        }
        let translated = rows.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return translated.isEmpty ? text : translated
    }

    private func srtTimeFixed(_ seconds: Double) -> String {
        let ms = max(0, Int(seconds * 1000))
        return String(format: "%02d:%02d:%02d,%03d", ms/3_600_000, (ms/60_000)%60, (ms/1000)%60, ms%1000)
    }
}
