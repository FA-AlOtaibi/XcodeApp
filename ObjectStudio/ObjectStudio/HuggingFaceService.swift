import Foundation
import UIKit

@MainActor
final class HuggingFaceService: ObservableObject {
    @Published var isBusy = false
    @Published var progressText = ""
    @Published var depthImage: UIImage?
    @Published var angleImages: [UIImage] = []
    @Published var modelURL: URL?
    @Published var errorMessage: String?

    @Published var qwenHost = "https://multimodalart-qwen-image-edit-angles-2.hf.space"
    @Published var hunyuanHost = "https://tencent-hunyuan3d-2-1.hf.space"
    @Published var depthModel = "depth-anything/Depth-Anything-V2-Base-hf"

    var token: String {
        get { KeychainStore.read("hf_token") }
        set { KeychainStore.save(newValue, key: "hf_token") }
    }

    func clearResults() {
        depthImage = nil
        angleImages = []
        modelURL = nil
        errorMessage = nil
    }

    func generateDepth(from image: UIImage) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true; progressText = "نحسب العمق…"; errorMessage = nil
        defer { isBusy = false; progressText = "" }
        do {
            guard let jpeg = image.jpegData(compressionQuality: 0.9),
                  let url = URL(string: "https://router.huggingface.co/hf-inference/models/\(depthModel)") else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("image/png", forHTTPHeaderField: "Accept")
            request.httpBody = jpeg
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard 200..<300 ~= http.statusCode else {
                let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw NSError(domain: "HF", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(text.prefix(500))])
            }
            guard let result = UIImage(data: data) else {
                throw NSError(domain: "HF", code: -1, userInfo: [NSLocalizedDescriptionKey: "خدمة Depth لم ترجع صورة. قد لا يكون الموديل متاحًا على Inference Provider حاليًا."])
            }
            depthImage = result
        } catch { errorMessage = "Depth: \(error.localizedDescription)" }
    }

    func generateAngles(from image: UIImage) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true; angleImages = []; errorMessage = nil
        defer { isBusy = false; progressText = "" }
        do {
            let client = try GradioClient(baseURL: qwenHost, token: token)
            progressText = "نرفع صورة المنتج…"
            let file = try await client.upload(image: image)
            let angles: [Double] = [-90, -45, 45, 90]
            for (index, angle) in angles.enumerated() {
                progressText = "نولد زاوية \(index + 1) من \(angles.count)…"
                let output = try await client.call(endpoint: "infer_edit_camera_angles", parameters: [
                    "image": .file(file),
                    "rotate_deg": .number(angle),
                    "move_forward": .number(0),
                    "vertical_tilt": .number(0),
                    "wideangle": .bool(false),
                    "seed": .number(Double(Int.random(in: 1...2_000_000_000))),
                    "randomize_seed": .bool(true),
                    "true_guidance_scale": .number(1.0),
                    "num_inference_steps": .number(4),
                    "height": .number(768),
                    "width": .number(768),
                    "prev_output": .null
                ], timeout: 600)
                if let url = GradioClient.firstURL(in: output, preferredExtensions: ["png","jpg","jpeg","webp"]) {
                    let local = try await client.download(url)
                    if let img = UIImage(contentsOfFile: local.path) { angleImages.append(img) }
                }
            }
            if angleImages.isEmpty {
                throw NSError(domain: "HF", code: -2, userInfo: [NSLocalizedDescriptionKey: "لم تُرجع خدمة الزوايا صورًا قابلة للتحميل."])
            }
        } catch { errorMessage = "الزوايا: \(error.localizedDescription)" }
    }

    func generate3D(from image: UIImage, textured: Bool = true) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true; modelURL = nil; errorMessage = nil
        defer { isBusy = false; progressText = "" }
        do {
            let client = try GradioClient(baseURL: hunyuanHost, token: token)
            progressText = "نرفع المنتج إلى Hunyuan3D…"
            let file = try await client.upload(image: image)
            progressText = textured ? "نبني المجسم والخامات…" : "نبني المجسم…"
            let endpoint = textured ? "generation_all" : "shape_generation"
            var params: [String: GradioValue] = [
                "caption": .null,
                "image": .file(file),
                "mv_image_front": .null,
                "mv_image_back": .null,
                "mv_image_left": .null,
                "mv_image_right": .null,
                "steps": .number(30),
                "guidance_scale": .number(5.0),
                "seed": .number(Double(Int.random(in: 1...2_000_000_000))),
                "octree_resolution": .number(256),
                "check_box_rembg": .bool(false),
                "num_chunks": .number(200000),
                "randomize_seed": .bool(true)
            ]
            if textured { params["max_facenum"] = .number(40000) }
            let output = try await client.call(endpoint: endpoint, parameters: params, timeout: 1200)
            guard let remote = GradioClient.firstURL(in: output, preferredExtensions: ["glb","obj"]) else {
                throw NSError(domain: "HF", code: -3, userInfo: [NSLocalizedDescriptionKey: "اكتمل Hunyuan3D لكن لم أجد رابط ملف GLB/OBJ في النتيجة."])
            }
            progressText = "ننزل ملف 3D…"
            modelURL = try await client.download(remote)
        } catch { errorMessage = "3D: \(error.localizedDescription)" }
    }
}
