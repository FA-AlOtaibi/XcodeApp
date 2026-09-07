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
    let history = PlantHistoryStore()

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
            do {
                let message = try await hf.generatePersona(for: result)
                persona = message
                history.add(diagnosis: result, persona: message)
            } catch {
                history.add(diagnosis: result, persona: nil)
                errorMessage = "تم التشخيص، لكن تعذر توليد صوت النبتة: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
