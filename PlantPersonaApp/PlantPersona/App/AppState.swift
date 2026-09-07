import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var analysis: VisualAnalysis?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published var selectedMediaKind: String = ""
    @Published var soundProfile: MediaSoundProfile?
    @Published var assistantAnswer: String?
    @Published var guidedStep: String?
    @Published var compareResult: String?
    @Published var selectedProfileID: UUID?

    let hf = HuggingFaceService()
    let intelligence = AYNIntelligenceService()
    let history = PlantHistoryStore()
    let workspace = AYNWorkspaceStore()
    let obd = OBDService()
    private let videoProcessor = VideoMediaProcessor()

    private var requestSerial = 0
    private var lastQuestion = ""
    private var lastQuestionAt = Date.distantPast

    func reset() {
        requestSerial += 1
        analysis = nil
        errorMessage = nil
        selectedImageData = nil
        selectedMediaKind = ""
        soundProfile = nil
        assistantAnswer = nil
        guidedStep = nil
        compareResult = nil
        isAnalyzing = false
    }

    func clearTransientResults() {
        assistantAnswer = nil
        guidedStep = nil
        compareResult = nil
        errorMessage = nil
    }

    func analyze(imageData: Data) async {
        guard !isAnalyzing else { return }
        let serial = beginRequest()
        selectedMediaKind = "صورة"
        soundProfile = nil
        selectedImageData = imageData
        defer { finishRequest(serial) }
        do {
            let result = try await hf.analyzeImage(imageData: imageData, obdContext: obd.contextText())
            guard serial == requestSerial else { return }
            analysis = result
            assistantAnswer = nil
            guidedStep = nil
            history.add(analysis: result)
            saveToProfile(result)
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func analyzeVideo(data: Data) async {
        guard !isAnalyzing else { return }
        let serial = beginRequest()
        selectedMediaKind = "فيديو"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ayn-\(UUID().uuidString).mov")
        defer {
            try? FileManager.default.removeItem(at: url)
            finishRequest(serial)
        }
        do {
            try data.write(to: url, options: .atomic)
            let processed = try await videoProcessor.process(url: url)
            guard serial == requestSerial else { return }
            selectedImageData = processed.frames.first
            soundProfile = processed.sound
            let result = try await hf.analyzeVideoFrames(processed.frames, sound: processed.sound, obdContext: obd.contextText())
            guard serial == requestSerial else { return }
            analysis = result
            assistantAnswer = nil
            guidedStep = nil
            history.add(analysis: result)
            saveToProfile(result)
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func ask(_ question: String, useCurrentContext: Bool = true) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isAnalyzing else { return }
        if trimmed == lastQuestion && Date().timeIntervalSince(lastQuestionAt) < 3 { return }
        lastQuestion = trimmed
        lastQuestionAt = Date()

        let serial = beginRequest(clearAnalysis: false)
        defer { finishRequest(serial) }
        do {
            let context = useCurrentContext ? currentContext() : nil
            let answer = try await intelligence.ask(trimmed, context: context)
            guard serial == requestSerial else { return }
            assistantAnswer = answer
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func reviewTechnician(_ statement: String) async {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }
        let serial = beginRequest(clearAnalysis: false)
        defer { finishRequest(serial) }
        do {
            let answer = try await intelligence.reviewTechnician(statement: trimmed, analysis: analysis, obd: obd.contextText())
            guard serial == requestSerial else { return }
            assistantAnswer = answer
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func nextGuidedStep(mode: String) async {
        guard analysis != nil, !isAnalyzing else { return }
        let serial = beginRequest(clearAnalysis: false)
        defer { finishRequest(serial) }
        do {
            let step = try await intelligence.guidedNextStep(current: analysis, mode: mode)
            guard serial == requestSerial else { return }
            guidedStep = step
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func compare(images: [Data], prompt: String) async {
        guard images.count >= 2, !isAnalyzing else { return }
        let serial = beginRequest(clearAnalysis: false)
        compareResult = nil
        defer { finishRequest(serial) }
        do {
            let result = try await intelligence.compare(images: images, prompt: prompt)
            guard serial == requestSerial else { return }
            compareResult = result
        } catch {
            guard serial == requestSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func reanalyzeWithOBD() async {
        guard let image = selectedImageData, !isAnalyzing else { return }
        await analyze(imageData: image)
    }

    private func beginRequest(clearAnalysis: Bool = true) -> Int {
        requestSerial += 1
        isAnalyzing = true
        errorMessage = nil
        if clearAnalysis { analysis = nil }
        return requestSerial
    }

    private func finishRequest(_ serial: Int) {
        // Requests are intentionally serialized. Always release UI interaction on completion.
        isAnalyzing = false
    }

    private func currentContext() -> String? {
        var parts: [String] = []
        if let a = analysis { parts.append("الصورة الحالية: \(a.title). \(a.summary)") }
        if let geo = analysis?.geo {
            let place = [geo.area, geo.city, geo.country].compactMap { $0 }.joined(separator: "، ")
            if !place.isEmpty { parts.append("تقدير المكان: \(place) (ثقة \(geo.confidence)%)") }
        }
        if let obdText = obd.contextText(), !obdText.isEmpty { parts.append("OBD:\n\(obdText)") }
        if let soundProfile { parts.append("مؤشرات صوت الفيديو: RMS \(soundProfile.rms), Peak \(soundProfile.peak)") }
        let result = parts.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    private func saveToProfile(_ result: VisualAnalysis) {
        guard let id = selectedProfileID else { return }
        let severity = result.automotive?.severity ?? (result.cautions.isEmpty ? "info" : "medium")
        workspace.addEvent(profileID: id, title: result.title, detail: result.summary, severity: severity)
    }
}
