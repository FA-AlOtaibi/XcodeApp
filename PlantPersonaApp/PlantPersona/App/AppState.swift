import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var analysis: VisualAnalysis?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?

    let hf = HuggingFaceService()
    let history = PlantHistoryStore()

    func reset() {
        analysis = nil
        errorMessage = nil
        selectedImageData = nil
    }

    func analyze(imageData: Data) async {
        isAnalyzing = true
        errorMessage = nil
        analysis = nil
        defer { isAnalyzing = false }

        do {
            let result = try await hf.analyzeImage(imageData: imageData)
            analysis = result
            history.add(analysis: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
