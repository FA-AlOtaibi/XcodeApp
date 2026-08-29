import SwiftUI
import AVKit
import AVFoundation
import Speech
import UIKit

// MARK: - Compact floating playback dock

struct FloatingPlaybackDock: View {
    @ObservedObject private var center = PlaybackCenter.shared

    var body: some View {
        if let item = center.item {
            HStack(spacing: 9) {
                Button { center.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button { center.seek(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.plain)

                Button { center.toggle() } label: {
                    Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)

                Button { center.seek(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18, weight: .medium))
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
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        LocalThumb(item: item)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 7)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: max(0, geo.size.width * CGFloat(min(1, center.currentTime / max(1, center.duration)))), height: 2)
                        .animation(.linear(duration: 0.2), value: center.currentTime)
                }
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 18)
            }
            .fullScreenCover(isPresented: $center.expanded) { ImmersivePlaybackView() }
        }
    }

    private func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

// MARK: - Immersive full screen player

struct ImmersivePlaybackView: View {
    @ObservedObject private var center = PlaybackCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item = center.item, let player = center.player {
                Group {
                    if item.isVideo {
                        PlayerSurface(player: player)
                    } else {
                        ZStack {
                            Color.black
                            VStack(spacing: 18) {
                                LocalThumb(item: item)
                                    .frame(width: 250, height: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                Text(item.url.deletingPathExtension().lastPathComponent)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

                if controlsVisible {
                    VStack(spacing: 0) {
                        topBar(item)
                        Spacer()
                        bottomControls
                    }
                    .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!controlsVisible)
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    private func topBar(_ item: LocalMedia) -> some View {
        HStack(spacing: 12) {
            Button {
                center.expanded = false
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.34), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(item.url.deletingPathExtension().lastPathComponent)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { center.currentTime }, set: { center.seek(to: $0); scheduleHide() }),
                in: 0...max(1, center.duration)
            )
            .tint(.white)

            HStack {
                Text(clock(center.currentTime))
                Spacer()
                Text("-\(clock(max(0, center.duration - center.currentTime)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 50) {
                Button { center.seek(by: -10); scheduleHide() } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 27, weight: .medium))
                }
                Button { center.toggle(); scheduleHide() } label: {
                    Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(.white, in: Circle())
                        .foregroundStyle(.black)
                }
                Button { center.seek(by: 10); scheduleHide() } label: {
                    Image(systemName: "goforward.10").font(.system(size: 27, weight: .medium))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func toggleControls() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard center.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.20)) { controlsVisible = false } }
        }
    }

    private func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        return controller
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) { uiViewController.player = player }
}

// MARK: - Swipeable row. Supports either direction so RTL/LTR both feel natural.

struct SwipeLibraryRow: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    let selecting: Bool
    let selected: Bool
    let toggle: () -> Void
    let actions: () -> Void

    @State private var offset: CGFloat = 0
    @State private var share = false
    @State private var confirmDelete = false

    private let reveal: CGFloat = 126

    var body: some View {
        ZStack {
            if !selecting { actionBackground }

            HStack(spacing: 10) {
                if selecting {
                    Button(action: toggle) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected ? Color(red: 0.27, green: 0.33, blue: 0.18) : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if selecting {
                        Button(action: toggle) { rowContent }.buttonStyle(.plain)
                    } else if item.isVideo || item.isAudio {
                        Button { PlaybackCenter.shared.play(item) } label: { rowContent }.buttonStyle(.plain)
                    } else if item.ext == "srt" || item.ext == "txt" {
                        NavigationLink { SubtitleViewerView(item: item) } label: { rowContent }.buttonStyle(.plain)
                    } else {
                        NavigationLink { MediaDetailView(model: model, item: item) } label: { rowContent }.buttonStyle(.plain)
                    }
                }

                if !selecting {
                    Button(action: actions) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .offset(x: offset)
            .contentShape(Rectangle())
            .highPriorityGesture(selecting ? nil : swipeGesture)
            .onTapGesture {
                if abs(offset) > 2 { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { offset = 0 } }
            }
        }
        .clipped()
        .sheet(isPresented: $share) { ActivityShareSheet(items: [item.url]) }
        .confirmationDialog("نقل الملف إلى سلة المهملات؟", isPresented: $confirmDelete) {
            Button("نقل إلى السلة", role: .destructive) {
                withAnimation {
                    model.moveToTrash(item)
                    model.refreshStorage()
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let x = value.translation.width
                offset = max(-reveal, min(reveal, x))
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                let actual = value.translation.width
                let direction: CGFloat = abs(predicted) > abs(actual) ? predicted : actual
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    if abs(direction) > 42 {
                        offset = direction < 0 ? -reveal : reveal
                    } else {
                        offset = 0
                    }
                }
            }
    }

    @ViewBuilder private var actionBackground: some View {
        HStack(spacing: 8) {
            if offset >= 0 {
                actionButtons
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                actionButtons
            }
        }
        .padding(.horizontal, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 7) {
            Button { share = true; offset = 0 } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 55, height: 55)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { confirmDelete = true; offset = 0 } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 55, height: 55)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            LocalThumb(item: item)
                .frame(width: 54, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.formattedBytes(item.size))
                    if !item.ext.isEmpty { Text(item.ext.uppercased()) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Stable subtitle generation. One language choice, sequential chunks, guarded callbacks.

extension AppModel {
    func translateVideoToSRTComplete(_ item: LocalMedia, targetLanguage: String) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }

        do {
            let auth = await speechAuthorizationV25()
            guard auth == .authorized else { throw AppError.message("اسمح بالتعرف على الكلام من إعدادات iOS") }

            let sourceAudio = try await speechSourceV25(item)
            defer { if sourceAudio != item.url { try? FileManager.default.removeItem(at: sourceAudio) } }

            let sourceAsset = AVURLAsset(url: sourceAudio)
            let total = try await sourceAsset.load(.duration).seconds
            guard total.isFinite, total > 0 else { throw AppError.message("تعذر قراءة مدة الصوت") }

            let firstLength = min(28.0, total)
            let firstChunk = try await exportSpeechChunkV25(asset: sourceAsset, start: 0, duration: firstLength)
            let locale = try await detectSpeechLocaleV25(url: firstChunk)
            try? FileManager.default.removeItem(at: firstChunk)

            let chunkLength = 38.0
            var cursor = 0.0
            var pieces: [SubtitlePieceV25] = []

            while cursor < total - 0.05 {
                try Task.checkCancellation()
                let length = min(chunkLength, total - cursor)
                let chunk = try await exportSpeechChunkV25(asset: sourceAsset, start: cursor, duration: length)
                do {
                    let result = try await recognizeV25(url: chunk, locale: locale)
                    for segment in result.bestTranscription.segments {
                        let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            pieces.append(.init(
                                start: cursor + segment.timestamp,
                                end: cursor + segment.timestamp + max(segment.duration, 0.18),
                                text: text
                            ))
                        }
                    }
                } catch {
                    // Skip only the failed chunk instead of crashing or losing the rest.
                }
                try? FileManager.default.removeItem(at: chunk)
                cursor += length
                try? await Task.sleep(for: .milliseconds(120))
            }

            guard !pieces.isEmpty else { throw AppError.message("لم أتمكن من التعرف على الكلام في هذا المقطع") }
            let groups = groupPiecesV25(pieces)

            var output = ""
            for (index, group) in groups.enumerated() {
                let translated = (try? await translateTextV25(group.text, target: targetLanguage)) ?? group.text
                output += "\(index + 1)\n\(srtTimeV25(group.start)) --> \(srtTimeV25(group.end))\n\(translated)\n\n"
            }

            let suffix = targetLanguage == "ar" ? "ar" : "en"
            let base = item.url.deletingPathExtension().lastPathComponent
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(base)-translated-\(suffix).srt")
            try? FileManager.default.removeItem(at: temp)
            try output.write(to: temp, atomically: true, encoding: .utf8)
            _ = try persist(temp, temp.lastPathComponent)
            refreshStorage()
            show("تم إنشاء الترجمة", .success)
        } catch is CancellationError {
            show("تم إلغاء الترجمة", .info)
        } catch {
            show(readable(error), .error)
        }
    }

    private func speechAuthorizationV25() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    private func speechSourceV25(_ item: LocalMedia) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty else { throw AppError.message("الفيديو لا يحتوي على صوت") }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز صوت الفيديو") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-source-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: url)
        export.outputURL = url
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر استخراج صوت الفيديو") }
        return url
    }

    private func exportSpeechChunkV25(asset: AVAsset, start: Double, duration: Double) async throws -> URL {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز جزء من الصوت") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-chunk-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: url)
        export.outputURL = url
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر تجهيز جزء من الصوت") }
        return url
    }

    private func detectSpeechLocaleV25(url: URL) async throws -> Locale {
        let candidates = [Locale(identifier: "en-US"), Locale(identifier: "ar-SA")]
        var bestLocale: Locale?
        var bestCount = 0
        for locale in candidates {
            if let result = try? await recognizeV25(url: url, locale: locale) {
                let count = result.bestTranscription.formattedString.count
                if count > bestCount { bestCount = count; bestLocale = locale }
            }
        }
        return bestLocale ?? Locale(identifier: "en-US")
    }

    private func recognizeV25(url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw AppError.message("التعرف على الكلام غير متاح الآن") }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            var recognitionTask: SFSpeechRecognitionTask?

            func finish(_ result: Result<SFSpeechRecognitionResult, Error>) {
                lock.lock()
                if resumed { lock.unlock(); return }
                resumed = true
                lock.unlock()
                recognitionTask?.cancel()
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal { finish(.success(result)) }
                else if let error { finish(.failure(error)) }
            }
        }
    }

    private struct SubtitlePieceV25 { let start: Double; let end: Double; let text: String }

    private func groupPiecesV25(_ pieces: [SubtitlePieceV25]) -> [SubtitlePieceV25] {
        var result: [SubtitlePieceV25] = []
        var words: [String] = []
        var start = 0.0
        var end = 0.0
        for piece in pieces.sorted(by: { $0.start < $1.start }) {
            if words.isEmpty { start = piece.start }
            words.append(piece.text)
            end = piece.end
            let combined = words.joined(separator: " ")
            if words.count >= 8 || end - start >= 3.6 || combined.count >= 62 {
                result.append(.init(start: start, end: max(end, start + 0.30), text: combined))
                words.removeAll(keepingCapacity: true)
            }
        }
        if !words.isEmpty { result.append(.init(start: start, end: max(end, start + 0.30), text: words.joined(separator: " "))) }
        return result
    }

    private func translateTextV25(_ text: String, target: String) async throws -> String {
        guard var parts = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else { return text }
        parts.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "q", value: text)
        ]
        guard let url = parts.url else { return text }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let rows = root.first as? [Any] else { throw AppError.message("تعذر ترجمة جزء من النص") }
        let translated = rows.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return translated.isEmpty ? text : translated
    }

    private func srtTimeV25(_ seconds: Double) -> String {
        let ms = max(0, Int(seconds * 1000))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}
