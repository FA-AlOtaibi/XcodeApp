import Foundation
import UIKit

@MainActor
final class HuggingFaceService: ObservableObject {
    @Published var isBusy = false
    @Published var progressText = ""
    @Published var depthImage: UIImage?
    @Published var angleImages: [UIImage] = []
    @Published var modelURL: URL?
    @Published var usdzURL: URL?
    @Published var errorMessage: String?

    @Published var qwenHost = "https://multimodalart-qwen-image-edit-angles-2.hf.space"
    @Published var hunyuanHost = "https://tencent-hunyuan3d-2.hf.space"
    @Published var depthHost = "https://depth-anything-depth-anything-v2.hf.space"
    @Published var depthModel = "depth-anything/Depth-Anything-V2"

    var token: String {
        get { KeychainStore.read("hf_token") }
        set { KeychainStore.save(newValue, key: "hf_token") }
    }

    func clearResults() {
        depthImage = nil
        angleImages = []
        modelURL = nil
        usdzURL = nil
        errorMessage = nil
    }

    func generateDepth(from image: UIImage) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true
        progressText = "نحسب العمق عبر Depth Anything V2…"
        errorMessage = nil
        defer { isBusy = false; progressText = "" }

        do {
            let client = try GradioClient(baseURL: depthHost, token: token)
            let file = try await client.upload(image: image)
            let output = try await client.call(endpoint: "on_submit", arguments: [.file(file)], timeout: 600)
            guard let array = output as? [Any] else {
                throw NSError(domain: "HF", code: -10, userInfo: [NSLocalizedDescriptionKey: "Depth Anything أعاد استجابة غير متوقعة."])
            }
            let candidate: Any = array.count > 1 ? array[1] : output
            guard let remote = GradioClient.firstURL(in: candidate, preferredExtensions: ["png", "jpg", "jpeg", "webp"]) ?? GradioClient.firstURL(in: output, preferredExtensions: ["png", "jpg", "jpeg", "webp"]) else {
                throw NSError(domain: "HF", code: -11, userInfo: [NSLocalizedDescriptionKey: "لم أجد ملف خريطة العمق في النتيجة."])
            }
            let local = try await client.download(remote)
            guard let result = UIImage(contentsOfFile: local.path) else {
                throw NSError(domain: "HF", code: -12, userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة خريطة العمق الناتجة."])
            }
            depthImage = result
        } catch {
            errorMessage = "Depth: \(error.localizedDescription)"
        }
    }

    func generateAngles(from image: UIImage) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true
        angleImages = []
        errorMessage = nil
        defer { isBusy = false; progressText = "" }

        do {
            let client = try GradioClient(baseURL: qwenHost, token: token)
            progressText = "نرفع صورة المنتج…"
            let file = try await client.upload(image: image)
            let angles: [Double] = [-90, -45, 45, 90]

            for (index, angle) in angles.enumerated() {
                progressText = "نولد زاوية \(index + 1) من \(angles.count)…"
                let output = try await client.callV2(
                    endpoint: "infer_edit_camera_angles",
                    namedArguments: [
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
                    ],
                    timeout: 900
                )

                guard let remote = GradioClient.firstURL(in: output, preferredExtensions: ["png", "jpg", "jpeg", "webp"]) else { continue }
                let local = try await client.download(remote)
                if let img = UIImage(contentsOfFile: local.path) { angleImages.append(img) }
            }

            if angleImages.isEmpty {
                throw NSError(domain: "HF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Qwen اشتغل لكن لم يرجع صور زوايا قابلة للتحميل."])
            }
        } catch {
            errorMessage = "الزوايا: \(error.localizedDescription)"
        }
    }

    func generate3D(from image: UIImage, textured: Bool = true) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true
        modelURL = nil
        usdzURL = nil
        errorMessage = nil
        defer { isBusy = false; progressText = "" }

        do {
            let client = try GradioClient(baseURL: hunyuanHost, token: token)
            progressText = "نرفع المنتج إلى Hunyuan3D 2.0…"
            let file = try await client.upload(image: image)
            progressText = textured ? "نبني المجسم والخامات…" : "نبني المجسم…"

            let endpoint = textured ? "generation_all" : "shape_generation"
            let output = try await client.call(endpoint: endpoint, arguments: hunyuanArguments(file: file), timeout: 1500)

            let remote: URL?
            if textured, let array = output as? [Any], array.count > 1 {
                remote = GradioClient.firstURL(in: array[1], preferredExtensions: ["glb", "obj", "usdz", "usd", "usdc"])
                    ?? GradioClient.firstURL(in: output, preferredExtensions: ["glb", "obj", "usdz", "usd", "usdc"])
            } else {
                remote = GradioClient.firstURL(in: output, preferredExtensions: ["glb", "obj", "usdz", "usd", "usdc"])
            }

            guard let remote else {
                throw NSError(domain: "HF", code: -3, userInfo: [NSLocalizedDescriptionKey: "اكتمل Hunyuan3D لكن لم أجد ملف 3D في النتيجة."])
            }

            progressText = "ننزل ملف 3D…"
            let local = try await client.download(remote)
            modelURL = local

            if ["obj", "usd", "usda", "usdc", "usdz"].contains(local.pathExtension.lowercased()) {
                progressText = "نجهز USDZ للـ AR…"
                usdzURL = try? USDZConverter.convertToUSDZ(local)
            }
        } catch {
            errorMessage = "3D: \(error.localizedDescription)"
        }
    }

    func generateARUSDZ(from image: UIImage) async {
        guard !token.isEmpty else { errorMessage = "أضف Hugging Face Token من الإعدادات أولاً."; return }
        isBusy = true
        usdzURL = nil
        errorMessage = nil
        defer { isBusy = false; progressText = "" }

        do {
            let client = try GradioClient(baseURL: hunyuanHost, token: token)
            progressText = "ننشئ المجسم للـ AR…"
            let file = try await client.upload(image: image)
            let output = try await client.call(endpoint: "shape_generation", arguments: hunyuanArguments(file: file), timeout: 1500)

            guard let remote = GradioClient.firstURL(in: output, preferredExtensions: ["usdz", "usd", "usdc", "obj", "glb"]) else {
                throw NSError(domain: "HF", code: -4, userInfo: [NSLocalizedDescriptionKey: "Hunyuan3D لم يرجع ملفًا مناسبًا."])
            }

            progressText = "ننزل المجسم…"
            let local = try await client.download(remote)
            modelURL = local
            let ext = local.pathExtension.lowercased()

            if ext == "usdz" { usdzURL = local; return }
            guard ["obj", "usd", "usda", "usdc"].contains(ext) else {
                throw NSError(domain: "HF", code: -5, userInfo: [NSLocalizedDescriptionKey: "رجعت الخدمة ملف \(ext.uppercased()). AR Quick Look يحتاج USDZ؛ استخدم 3D أولاً أو ملف OBJ/USD."])
            }
            progressText = "نحوّل إلى USDZ…"
            usdzURL = try USDZConverter.convertToUSDZ(local)
        } catch {
            errorMessage = "AR: \(error.localizedDescription)"
        }
    }

    private func hunyuanArguments(file: GradioFileData) -> [GradioValue] {
        [
            .null,
            .file(file),
            .null,
            .null,
            .null,
            .null,
            .number(30),
            .number(5.0),
            .number(Double(Int.random(in: 1...10_000_000))),
            .number(256),
            .bool(false),
            .number(200000),
            .bool(true)
        ]
    }
}
