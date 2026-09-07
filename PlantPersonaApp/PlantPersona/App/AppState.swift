import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var analysis: VisualAnalysis?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published var selectedMediaKind: String = "صورة"
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

    func reset() {
        analysis = nil
        errorMessage = nil
        selectedImageData = nil
        selectedMediaKind = "صورة"
        soundProfile = nil
        assistantAnswer = nil
        guidedStep = nil
        compareResult = nil
    }

    func analyze(imageData: Data) async {
        isAnalyzing = true
        errorMessage = nil
        analysis = nil
        selectedMediaKind = "صورة"
        soundProfile = nil
        defer { isAnalyzing = false }
        do {
            let result = try await hf.analyzeImage(imageData: imageData, obdContext: obd.contextText())
            analysis = result
            history.add(analysis: result)
            saveToProfile(result)
        } catch { errorMessage = error.localizedDescription }
    }

    func analyzeVideo(data: Data) async {
        isAnalyzing = true
        errorMessage = nil
        analysis = nil
        selectedMediaKind = "فيديو + صوت"
        defer { isAnalyzing = false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ayn-\(UUID().uuidString).mov")
        do {
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            let processed = try await videoProcessor.process(url: url)
            selectedImageData = processed.frames.first
            soundProfile = processed.sound
            let result = try await hf.analyzeVideoFrames(processed.frames, sound: processed.sound, obdContext: obd.contextText())
            analysis = result
            history.add(analysis: result)
            saveToProfile(result)
        } catch { errorMessage = error.localizedDescription }
    }

    func ask(_ question: String) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAnalyzing = true; errorMessage = nil; defer { isAnalyzing = false }
        do {
            assistantAnswer = try await intelligence.ask(question, context: currentContext())
        } catch { errorMessage = error.localizedDescription }
    }

    func reviewTechnician(_ statement: String) async {
        isAnalyzing = true; errorMessage = nil; defer { isAnalyzing = false }
        do { assistantAnswer = try await intelligence.reviewTechnician(statement: statement, analysis: analysis, obd: obd.contextText()) }
        catch { errorMessage = error.localizedDescription }
    }

    func nextGuidedStep(mode: String) async {
        isAnalyzing = true; errorMessage = nil; defer { isAnalyzing = false }
        do { guidedStep = try await intelligence.guidedNextStep(current: analysis, mode: mode) }
        catch { errorMessage = error.localizedDescription }
    }

    func compare(images: [Data], prompt: String) async {
        isAnalyzing = true; errorMessage = nil; compareResult = nil; defer { isAnalyzing = false }
        do { compareResult = try await intelligence.compare(images: images, prompt: prompt) }
        catch { errorMessage = error.localizedDescription }
    }

    func reanalyzeWithOBD() async {
        guard let image = selectedImageData else {
            errorMessage = "صوّر أو اختر وسائط أولًا ثم أعد التحليل بعد فحص OBD."
            return
        }
        await analyze(imageData: image)
    }

    private func currentContext() -> String {
        var parts: [String] = []
        if let a = analysis { parts.append("آخر تحليل: \(a.title) — \(a.summary)") }
        let obdText = obd.contextText(); if !obdText.isEmpty { parts.append("OBD:\n\(obdText)") }
        if let soundProfile { parts.append("الصوت: RMS \(soundProfile.rms), Peak \(soundProfile.peak)") }
        return parts.joined(separator: "\n\n")
    }

    private func saveToProfile(_ result: VisualAnalysis) {
        guard let id = selectedProfileID else { return }
        let severity = result.automotive?.severity ?? (result.cautions.isEmpty ? "info" : "medium")
        workspace.addEvent(profileID: id, title: result.title, detail: result.summary, severity: severity)
    }
}
