import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import Speech

// MARK: - Library rebuilt on native List so iOS swipeActions work reliably

struct LibraryViewV26: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var filter: MediaFilter = .all
    @State private var sort: SortMode = .newest
    @State private var picker: [PhotosPickerItem] = []
    @State private var fileImport = false
    @State private var actionItem: LocalMedia?
    @State private var shareItem: LocalMedia?
    @State private var selecting = false
    @State private var selected: Set<String> = []

    private let olive = Color(red: 0.27, green: 0.33, blue: 0.18)

    private var items: [LocalMedia] {
        var a = model.library.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        switch filter {
        case .all: break
        case .image: a = a.filter { $0.isImage || $0.ext == "gif" }
        case .video: a = a.filter { $0.isVideo }
        case .audio: a = a.filter { $0.isAudio }
        case .document: a = a.filter { !$0.isImage && !$0.isVideo && !$0.isAudio && $0.ext != "gif" }
        }
        switch sort {
        case .newest: a.sort { $0.createdAt > $1.createdAt }
        case .oldest: a.sort { $0.createdAt < $1.createdAt }
        case .name: a.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        case .size: a.sort { $0.size > $1.size }
        }
        return a
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("بحث", text: $search)
                            .textInputAutocapitalization(.never)
                        Menu {
                            ForEach(SortMode.allCases) { mode in Button(mode.rawValue) { sort = mode } }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundStyle(olive)
                        }
                    }
                    .padding(.vertical, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(MediaFilter.allCases) { f in
                                Button(f.rawValue) { filter = f }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(filter == f ? olive : Color.primary.opacity(0.07), in: Capsule())
                                    .foregroundStyle(filter == f ? .white : .primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $picker, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                            Label("من الصور", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(olive)

                        Button { fileImport = true } label: { Image(systemName: "folder.badge.plus") }
                            .buttonStyle(.bordered)

                        NavigationLink { TrashView(model: model) } label: {
                            Image(systemName: "trash.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                    }

                    if selecting {
                        HStack {
                            Button(selected.count == items.count && !items.isEmpty ? "إلغاء تحديد الكل" : "تحديد الكل") {
                                selected = selected.count == items.count ? [] : Set(items.map(\.id))
                            }
                            Spacer()
                            Text("\(selected.count) محدد").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)

                if items.isEmpty {
                    ContentUnavailableView("المكتبة فارغة", systemImage: "folder")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(items) { item in
                            row(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label("حذف", systemImage: "trash.fill")
                                    }
                                    Button { shareItem = item } label: {
                                        Label("مشاركة", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { actionItem = item } label: {
                                        Label("أدوات", systemImage: "ellipsis")
                                    }
                                    .tint(olive)
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("المكتبة")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? "تم" : "تحديد") {
                        selecting.toggle()
                        if !selecting { selected.removeAll() }
                    }
                }
                if selecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash") }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .onAppear { model.refreshStorage(); model.purgeExpiredTrash() }
            .onChange(of: picker) { _, new in
                Task {
                    for p in new {
                        if let data = try? await p.loadTransferable(type: Data.self) { model.importImageData(data, ext: "jpg") }
                    }
                    picker = []
                }
            }
            .fileImporter(isPresented: $fileImport, allowedContentTypes: [.movie, .image, .audio, .pdf, .data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(model.importFile) }
            }
            .sheet(item: $actionItem) { MediaQuickActionsSheet(model: model, item: $0) }
            .sheet(item: $shareItem) { ActivityShareSheet(items: [$0.url]) }
        }
    }

    @ViewBuilder private func row(_ item: LocalMedia) -> some View {
        HStack(spacing: 10) {
            if selecting {
                Button { toggle(item) } label: {
                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected.contains(item.id) ? olive : .secondary)
                }.buttonStyle(.plain)
            }

            Group {
                if selecting {
                    Button { toggle(item) } label: { rowContent(item) }.buttonStyle(.plain)
                } else if item.isVideo || item.isAudio {
                    Button { PlaybackCenter.shared.play(item) } label: { rowContent(item) }.buttonStyle(.plain)
                } else if item.ext.lowercased() == "srt" || item.ext.lowercased() == "txt" {
                    NavigationLink { SubtitleViewerView(item: item) } label: { rowContent(item) }.buttonStyle(.plain)
                } else {
                    NavigationLink { MediaDetailView(model: model, item: item) } label: { rowContent(item) }.buttonStyle(.plain)
                }
            }

            if !selecting {
                Button { actionItem = item } label: {
                    Image(systemName: "ellipsis").frame(width: 34, height: 34)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func rowContent(_ item: LocalMedia) -> some View {
        HStack(spacing: 10) {
            LocalThumb(item: item)
                .frame(width: 55, height: 49)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.formattedBytes(item.size))
                    if !item.ext.isEmpty { Text(item.ext.uppercased()) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ item: LocalMedia) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    private func delete(_ item: LocalMedia) {
        withAnimation { model.moveToTrash(item); model.refreshStorage() }
    }

    private func deleteSelected() {
        model.library.filter { selected.contains($0.id) }.forEach { model.moveToTrash($0) }
        selected.removeAll(); selecting = false; model.refreshStorage()
    }
}

// MARK: - Translation UI with explicit target language

struct TranslationChoiceSheetV26: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var progressText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button { run("ar") } label: {
                    Label("ترجمة كاملة إلى العربية", systemImage: "character.book.closed")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                .buttonStyle(.borderedProminent).disabled(busy)

                Button { run("en") } label: {
                    Label("ترجمة كاملة إلى الإنجليزية", systemImage: "character.book.closed")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                .buttonStyle(.bordered).disabled(busy)

                if busy {
                    HStack(spacing: 10) { ProgressView(); Text(progressText.isEmpty ? "جارٍ معالجة المقطع كاملًا…" : progressText) }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("ترجمة الفيديو")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(285), .medium])
    }

    private func run(_ target: String) {
        guard !busy else { return }
        busy = true
        progressText = target == "ar" ? "جارٍ إنشاء ترجمة عربية…" : "جارٍ إنشاء ترجمة إنجليزية…"
        Task {
            await model.translateVideoToSRTV26(item, targetLanguage: target)
            busy = false
            if model.notice?.style != .error { dismiss() }
        }
    }
}

// MARK: - Full-length subtitle pipeline

extension AppModel {
    func translateVideoToSRTV26(_ item: LocalMedia, targetLanguage rawTarget: String) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        let target = normalizeTargetV26(rawTarget)

        do {
            let auth = await speechAuthorizationV26()
            guard auth == .authorized else { throw AppError.message("اسمح بالتعرف على الكلام من إعدادات iOS") }

            let audioURL = try await speechAudioV26(item)
            defer { if audioURL != item.url { try? FileManager.default.removeItem(at: audioURL) } }

            let duration = try await AVURLAsset(url: audioURL).load(.duration).seconds
            guard duration.isFinite && duration > 0 else { throw AppError.message("تعذر قراءة مدة المقطع") }

            let preferredLocale = try await detectSpeechLocaleV26(audioURL: audioURL, duration: duration)
            let alternateLocale = preferredLocale.identifier.hasPrefix("ar") ? Locale(identifier: "en-US") : Locale(identifier: "ar-SA")

            let window = 18.0
            let overlap = 0.8
            var cursor = 0.0
            var pieces: [SubtitlePieceV26] = []
            var lastAcceptedEnd = -1.0

            while cursor < duration - 0.05 {
                let length = min(window, duration - cursor)
                let chunk = try await exportChunkV26(audioURL: audioURL, start: cursor, duration: length)
                defer { try? FileManager.default.removeItem(at: chunk) }

                var result = try? await recognizeChunkV26(url: chunk, locale: preferredLocale)
                if result?.bestTranscription.segments.isEmpty != false {
                    result = try? await recognizeChunkV26(url: chunk, locale: alternateLocale)
                }

                if let result {
                    for seg in result.bestTranscription.segments {
                        let absStart = cursor + seg.timestamp
                        let absEnd = absStart + max(seg.duration, 0.18)
                        if cursor > 0 && absEnd <= lastAcceptedEnd + 0.08 { continue }
                        let text = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        pieces.append(.init(start: absStart, end: absEnd, text: text))
                        lastAcceptedEnd = max(lastAcceptedEnd, absEnd)
                    }
                }

                if cursor + length >= duration { break }
                cursor += max(1, window - overlap)
            }

            guard !pieces.isEmpty else { throw AppError.message("لم أتمكن من التعرف على الكلام في المقطع") }
            let groups = groupPiecesV26(pieces)

            var srt = ""
            for (index, group) in groups.enumerated() {
                let translated = try await translateStrictV26(group.text, target: target)
                srt += "\(index + 1)\n\(srtTimeV26(group.start)) --> \(srtTimeV26(group.end))\n\(translated)\n\n"
            }

            let base = item.url.deletingPathExtension().lastPathComponent
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(base)-translated-\(target).srt")
            try? FileManager.default.removeItem(at: tmp)
            try srt.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage()
            show(target == "ar" ? "تم إنشاء الترجمة العربية كاملة" : "تم إنشاء الترجمة الإنجليزية كاملة", .success)
        } catch {
            show(readable(error), .error)
        }
    }

    private func normalizeTargetV26(_ raw: String) -> String {
        let x = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if x == "ar" || x.hasPrefix("ar-") || x.contains("arab") || x.contains("عرب") { return "ar" }
        return "en"
    }

    private func speechAuthorizationV26() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    }

    private func speechAudioV26(_ item: LocalMedia) async throws -> URL {
        if item.isAudio { return item.url }
        let asset = AVURLAsset(url: item.url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("تعذر تجهيز صوت الفيديو")
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("speech-source-\(UUID().uuidString).m4a")
        export.outputURL = out; export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر استخراج صوت الفيديو") }
        return out
    }

    private func detectSpeechLocaleV26(audioURL: URL, duration: Double) async throws -> Locale {
        let probe = try await exportChunkV26(audioURL: audioURL, start: 0, duration: min(14, duration))
        defer { try? FileManager.default.removeItem(at: probe) }
        let en = try? await recognizeChunkV26(url: probe, locale: Locale(identifier: "en-US"))
        let ar = try? await recognizeChunkV26(url: probe, locale: Locale(identifier: "ar-SA"))
        let enScore = en?.bestTranscription.formattedString.filter { !$0.isWhitespace }.count ?? 0
        let arScore = ar?.bestTranscription.formattedString.filter { !$0.isWhitespace }.count ?? 0
        if enScore == 0 && arScore == 0 { throw AppError.message("تعذر تحديد لغة الكلام") }
        return arScore > enScore ? Locale(identifier: "ar-SA") : Locale(identifier: "en-US")
    }

    private func exportChunkV26(audioURL: URL, start: Double, duration: Double) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("تعذر تجهيز جزء من الصوت")
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a")
        export.outputURL = out; export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
        await export.export()
        guard export.status == .completed else { throw export.error ?? AppError.message("تعذر تجهيز جزء من الصوت") }
        return out
    }

    private func recognizeChunkV26(url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppError.message("خدمة التعرف على الكلام غير متاحة الآن")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = false }

        return try await withCheckedThrowingContinuation { continuation in
            final class State { var finished = false; var task: SFSpeechRecognitionTask? }
            let state = State()
            state.task = recognizer.recognitionTask(with: request) { result, error in
                if state.finished { return }
                if let result, result.isFinal {
                    state.finished = true
                    continuation.resume(returning: result)
                    state.task?.cancel()
                } else if let error {
                    state.finished = true
                    continuation.resume(throwing: error)
                    state.task?.cancel()
                }
            }
        }
    }

    private struct SubtitlePieceV26 {
        let start: Double
        let end: Double
        let text: String
    }

    private func groupPiecesV26(_ input: [SubtitlePieceV26]) -> [SubtitlePieceV26] {
        let sorted = input.sorted { $0.start < $1.start }
        var out: [SubtitlePieceV26] = []
        var words: [String] = []
        var start = 0.0
        var end = 0.0

        for p in sorted {
            if words.isEmpty { start = p.start }
            words.append(p.text)
            end = max(end, p.end)
            let joined = words.joined(separator: " ")
            if end - start >= 3.2 || words.count >= 9 || joined.count >= 64 {
                out.append(.init(start: start, end: max(end, start + 0.35), text: joined))
                words.removeAll(keepingCapacity: true)
                end = 0
            }
        }
        if !words.isEmpty { out.append(.init(start: start, end: max(end, start + 0.35), text: words.joined(separator: " "))) }
        return out
    }

    private func translateStrictV26(_ text: String, target: String) async throws -> String {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                guard var parts = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else { throw AppError.message("تعذر تجهيز الترجمة") }
                parts.queryItems = [
                    .init(name: "client", value: "gtx"), .init(name: "sl", value: "auto"),
                    .init(name: "tl", value: target), .init(name: "dt", value: "t"), .init(name: "q", value: text)
                ]
                guard let url = parts.url else { throw AppError.message("تعذر تجهيز الترجمة") }
                var request = URLRequest(url: url); request.timeoutInterval = 25
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let root = try JSONSerialization.jsonObject(with: data) as? [Any],
                      let rows = root.first as? [Any] else { throw AppError.message("خدمة الترجمة لم تستجب") }
                let translated = rows.compactMap { ($0 as? [Any])?.first as? String }.joined()
                guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("وصلت ترجمة فارغة") }

                if target == "ar" && text.range(of: "[A-Za-z]", options: .regularExpression) != nil && translated.range(of: "[\u{0600}-\u{06FF}]", options: .regularExpression) == nil {
                    throw AppError.message("لم تصل ترجمة عربية صحيحة")
                }
                return translated
            } catch {
                lastError = error
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(450 * (attempt + 1))) }
            }
        }
        throw lastError ?? AppError.message("تعذر ترجمة جزء من المقطع")
    }

    private func srtTimeV26(_ value: Double) -> String {
        let ms = max(0, Int(value * 1000))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}
