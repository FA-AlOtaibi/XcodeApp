import SwiftUI
import SceneKit

struct ModelViewer: View {
    let fileURL: URL
    @State private var scene: SCNScene?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color(white: 0.07)
            if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else if let error {
                ContentUnavailableView("تعذر عرض المجسم", systemImage: "cube", description: Text(error))
            } else {
                ProgressView("تحميل المجسم…")
            }
        }
        .task(id: fileURL) {
            scene = nil
            error = nil
            do { scene = try await USDZConverter.loadScene(fileURL) }
            catch { self.error = error.localizedDescription }
        }
    }
}
