import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var analysis: VisualAnalysis?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published var selectedMediaKind: String = "صورة"
    @Published var soundProfile: MediaSoundProfile?

    let hf = HuggingFaceService()
    let history = PlantHistoryStore()
    let obd = OBDService()
    private let videoProcessor = VideoMediaProcessor()

    func reset() {
        analysis = nil
        errorMessage = nil
        selectedImageData = nil
        selectedMediaKind = "صورة"
        soundProfile = nil
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
        } catch {
            errorMessage = error.localizedDescription
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reanalyzeWithOBD() async {
        guard let image = selectedImageData else {
            errorMessage = "صوّر أو اختر وسائط أولًا ثم أعد التحليل بعد فحص OBD."
            return
        }
        await analyze(imageData: image)
    }
}
