import Foundation
import SceneKit
import GLTFKit2

struct USDZConverter {
    static func loadScene(_ url: URL) async throws -> SCNScene {
        if ["glb", "gltf"].contains(url.pathExtension.lowercased()) {
            return try await withCheckedThrowingContinuation { continuation in
                GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
                    if status == .error {
                        continuation.resume(throwing: error ?? GradioClient.ClientError.missingOutput)
                    } else if status == .complete {
                        guard let asset else {
                            continuation.resume(throwing: GradioClient.ClientError.missingOutput)
                            return
                        }
                        continuation.resume(returning: SCNScene(gltfAsset: asset))
                    }
                }
            }
        }
        return try SCNScene(url: url, options: nil)
    }

    static func convertToUSDZ(_ sourceURL: URL) async throws -> URL {
        if sourceURL.pathExtension.lowercased() == "usdz" { return sourceURL }
        let scene = try await loadScene(sourceURL)
        let output = sourceURL.deletingPathExtension().appendingPathExtension("usdz")
        guard scene.write(to: output, options: nil, delegate: nil, progressHandler: nil),
              let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw GradioClient.ClientError.server("لم ينجح تصدير USDZ. بقي ملف المجسم الأصلي محفوظًا.")
        }
        return output
    }
}
