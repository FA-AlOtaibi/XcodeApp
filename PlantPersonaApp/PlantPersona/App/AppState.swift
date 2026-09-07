import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var diagnosis: PlantDiagnosis?
    @Published var persona: PlantPersonaMessage?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published var showSettings = false

    let hf = HuggingFaceService()
    let speech = PlantSpeechService()

    func reset() {
        diagnosis = nil
        persona = nil
        errorMessage = nil
        selectedImageData = nil
        speech.stop()
    }

    func analyze(imageData: Data) async {
        isAnalyzing = true
        errorMessage = nil
        diagnosis = nil
        persona = nil
        defer { isAnalyzing = false }

        do {
            let result = try await hf.diagnosePlant(imageData: imageData)
            diagnosis = result
            let message = try await hf.generatePersona(for: result)
            persona = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
