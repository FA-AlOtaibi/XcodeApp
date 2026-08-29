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
    private var remoteCommandsInstalled = false

    private init() {
        installRemoteCommands()
    }

    func play(_ media: LocalMedia) {
        guard media.isVideo || media.isAudio else { return }

        if item?.url == media.url, let player {
            if player.timeControlStatus != .playing { player.play() }
            isPlaying = true
            updateNowPlaying()
            return
        }

        stop(removeItem: false)
        item = media
        currentTime = 0
        duration = 1

        let p = AVPlayer(url: media.url)
        p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player = p

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }

        Task {
            if let d = try? await AVURLAsset(url: media.url).load(.duration).seconds,
               d.isFinite, d > 0 {
                duration = d
                updateNowPlaying()
            }
        }

        observer = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak p] time in
            Task { @MainActor in
                guard let self, let p else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                self.isPlaying = p.timeControlStatus == .playing
                self.updateNowPlaying()
            }
        }

        p.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.15 {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let value = min(max(0, seconds), max(0, duration))
        currentTime = value
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlaying()
    }

    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func installRemoteCommands() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let command = MPRemoteCommandCenter.shared()

        command.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                player.play(); self.isPlaying = true; self.updateNowPlaying()
            }
            return .success
        }
        command.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player?.pause(); self.isPlaying = false; self.updateNowPlaying()
            }
            return .success
        }
        command.skipForwardCommand.preferredIntervals = [10]
        command.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: 10) }
            return .success
        }
        command.skipBackwardCommand.preferredIntervals = [10]
        command.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: -10) }
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
            Group {
                if center.expanded {
                    expandedPlayer(item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    compactPlayer(item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: center.expanded)
        }
    }

    private func compactPlayer(_ item: LocalMedia) -> some View {
        VStack(spacing: 0) {
            ProgressView(value: center.currentTime, total: max(1, center.duration))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack(spacing: 11) {
                Button { center.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Button { center.seek(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 19, weight: .medium))
                }
                .buttonStyle(.plain)

                Button { center.toggle() } label: {
                    Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Button { center.seek(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 19, weight: .medium))
                }
                .buttonStyle(.plain)

                Button { center.expanded = true } label: {
                    HStack(spacing: 9) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.url.deletingPathExtension().lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(clock(center.currentTime))  •  \(clock(center.duration))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        LocalThumb(item: item)
                            .frame(width: 46, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func expandedPlayer(_ item: LocalMedia) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { center.expanded = false } label: {
                    Label("تصغير", systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button { center.stop() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let player = center.player {
                Group {
                    if item.isVideo {
                        VideoPlayer(player: player)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                            VStack(spacing: 10) {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 62))
                                Text(item.url.deletingPathExtension().lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: item.isVideo ? 220 : 150)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            VStack(spacing: 5) {
                Slider(
                    value: Binding(
                        get: { center.currentTime },
                        set: { center.seek(to: $0) }
                    ),
                    in: 0...max(1, center.duration)
                )
                HStack {
                    Text(clock(center.currentTime))
                    Spacer()
                    Text("-\(clock(max(0, center.duration - center.currentTime)))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 38) {
                Button { center.seek(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.title2)
                }
                Button { center.toggle() } label: {
                    Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.bold())
                        .frame(width: 56, height: 56)
                        .background(Color.primary.opacity(0.09), in: Circle())
                }
                Button { center.seek(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.title2)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .shadow(radius: 18, y: -3)
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = max(0, Int(seconds))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
        }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

extension AppModel {
    func translateVideoToSRTFixed(_ item: LocalMedia, targetLanguage: String) async {
        guard item.isVideo || item.isAudio else {
            show("اختر فيديو أو ملف صوتي", .info)
            return
        }

        show("جارٍ استخراج الكلام وترجمته…", .info)

        do {
            let auth = await requestSpeechAuthorizationFixed()
            guard auth == .authorized else {
                throw AppError.message("فعّل إذن التعرف على الكلام من إعدادات الآيفون")
            }

            let speechURL = try await makeSpeechInputFixed(item)
            defer {
                if speechURL != item.url { try? FileManager.default.removeItem(at: speechURL) }
            }

            let localeIDs = ["ar-SA", "en-US", "en-GB"]
            var best: SFSpeechRecognitionResult?
            var lastError: Error?

            for id in localeIDs {
                do {
                    let result = try await recognizeSpeechFixed(speechURL, locale: Locale(identifier: id))
                    if result.bestTranscription.formattedString.count > (best?.bestTranscription.formattedString.count ?? 0) {
                        best = result
                    }
                } catch {
                    lastError = error
                }
            }

            guard let result = best, !result.bestTranscription.segments.isEmpty else {
                throw lastError ?? AppError.message("لم أتمكن من التعرف على الكلام في هذا المقطع")
            }

            let groups = makeSubtitleGroupsFixed(result.bestTranscription.segments)
            guard !groups.isEmpty else { throw AppError.message("لم يتم العثور على كلام قابل للترجمة") }

            var srt = ""
            for (idx, group) in groups.enumerated() {
                let translated = try await translateTextFixed(group.text, target: targetLanguage)
                srt += "\(idx + 1)\n\(srtTimeFixed(group.start)) --> \(srtTimeFixed(group.end))\n\(translated)\n\n"
            }

            let suffix = targetLanguage == "ar" ? "ar" : "en"
            let base = item.url.deletingPathExtension().lastPathComponent
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(base)-translated-\(suffix).srt")
            try? FileManager.default.removeItem(at: tmp)
            try srt.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage()
            show("تم إنشاء الترجمة وحفظها في المكتبة", .success)
        } catch {
            show(readable(error), .error)
        }
    }

    private func requestSpeechAuthorizationFixed() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func makeSpeechInputFixed(_ item: LocalMedia) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else {
            throw AppError.message("الفيديو لا يحتوي على مسار صوت")
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("تعذر تجهيز صوت الفيديو")
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: tmp)
        export.outputURL = tmp
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else {
            throw export.error ?? AppError.message("تعذر استخراج الصوت للترجمة")
        }
        return tmp
    }

    private func recognizeSpeechFixed(_ url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppError.message("خدمة التعرف على الكلام غير متاحة الآن")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false
        }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal, !finished {
                    finished = true
                    continuation.resume(returning: result)
                } else if let error, !finished {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
            _ = task
        }
    }

    private struct SubtitleGroupFixed {
        let start: Double
        let end: Double
        let text: String
    }

    private func makeSubtitleGroupsFixed(_ segments: [SFTranscriptionSegment]) -> [SubtitleGroupFixed] {
        var output: [SubtitleGroupFixed] = []
        var words: [String] = []
        var start = 0.0
        var end = 0.0

        for seg in segments {
            if words.isEmpty { start = seg.timestamp }
            words.append(seg.substring)
            end = seg.timestamp + seg.duration

            if words.count >= 9 || end - start >= 3.8 {
                output.append(.init(
                    start: start,
                    end: max(end, start + 0.35),
                    text: words.joined(separator: " ")
                ))
                words.removeAll(keepingCapacity: true)
            }
        }

        if !words.isEmpty {
            output.append(.init(
                start: start,
                end: max(end, start + 0.35),
                text: words.joined(separator: " ")
            ))
        }
        return output
    }

    private func translateTextFixed(_ text: String, target: String) async throws -> String {
        guard var parts = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else {
            return text
        }

        parts.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "q", value: text)
        ]

        guard let url = parts.url else { return text }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let rows = root.first as? [Any] else {
            throw AppError.message("تعذر الاتصال بخدمة الترجمة")
        }

        let translated = rows.compactMap { ($0 as? [Any])?.first as? String }.joined()
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.message("خدمة الترجمة أعادت نتيجة فارغة")
        }
        return translated
    }

    private func srtTimeFixed(_ seconds: Double) -> String {
        let ms = max(0, Int(seconds * 1000))
        return String(
            format: "%02d:%02d:%02d,%03d",
            ms / 3_600_000,
            (ms / 60_000) % 60,
            (ms / 1000) % 60,
            ms % 1000
        )
    }
}
