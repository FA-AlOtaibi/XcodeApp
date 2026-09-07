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

    @Published var qwenHost = UserDefaults.standard.string(forKey: "qwenHost") ?? "https://multimodalart-qwen-image-edit-angles-2.hf.space" {
        didSet { UserDefaults.standard.set(qwenHost, forKey: "qwenHost") }
    }
    @Published var hunyuanHost = UserDefaults.standard.string(forKey: "hunyuanHost") ?? "https://tencent-hunyuan3d-2.hf.space" {
        didSet { UserDefaults.standard.set(hunyuanHost, forKey: "hunyuanHost") }
    }
    @Published var depthHost = UserDefaults.standard.string(forKey: "depthHost") ?? "https://depth-anything-depth-anything-v2.hf.space" {
        didSet { UserDefaults.standard.set(depthHost, forKey: "depthHost") }
    }
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
        guard !isBusy else { return }
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
            guard let remote = await client.outputURL(in: candidate, preferredExtensions: ["png", "jpg", "jpeg", "webp"]) else {
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
        guard !isBusy else { return }
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
                let output = try await client.callDiscovered(
                    endpoint: "infer_and_show_video_button",
                    values: [
                        "param_0": .file(file), "param_1": .number(angle),
                        "param_2": .number(0), "param_3": .number(0),
                        "param_4": .bool(false), "param_5": .number(42),
                        "param_6": .bool(false), "param_7": .number(1),
                        "param_8": .number(4), "param_9": .number(768),
                        "param_10": .number(768), "param_11": .null
                    ],
                    timeout: 900
                )

                guard let remote = await client.outputURL(in: output, preferredExtensions: ["png", "jpg", "jpeg", "webp"]) else { throw GradioClient.ClientError.missingOutput }
                let local = try await client.download(remote)
                guard let img = UIImage(contentsOfFile: local.path) else { throw GradioClient.ClientError.missingOutput }
                angleImages.append(img)
            }

            if angleImages.isEmpty {
                throw NSError(domain: "HF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Qwen اشتغل لكن لم يرجع صور زوايا قابلة للتحميل."])
            }
        } catch {
            errorMessage = "الزوايا: \(error.localizedDescription)"
        }
    }

    func generate3D(from image: UIImage, textured: Bool = true) async {
        guard !isBusy else { return }
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
            let output = try await client.callDiscovered(endpoint: endpoint, values: hunyuanArguments(file: file), timeout: 1500)

            let remote: URL?
            if textured, let array = output as? [Any], array.count > 1 {
                remote = await client.outputURL(in: array[1], preferredExtensions: ["glb", "obj", "usdz", "usd", "usdc"])

            } else {
                remote = await client.outputURL(in: output, preferredExtensions: ["glb", "obj", "usdz", "usd", "usdc"])
            }

            guard let remote else {
                throw NSError(domain: "HF", code: -3, userInfo: [NSLocalizedDescriptionKey: "اكتمل Hunyuan3D لكن لم أجد ملف 3D في النتيجة."])
            }

            progressText = "ننزل ملف 3D…"
            let local = try await client.download(remote)
            modelURL = local

            progressText = "نجهز USDZ للـ AR…"
            do { usdzURL = try await USDZConverter.convertToUSDZ(local) }
            catch { errorMessage = "المجسم جاهز. تعذر تصدير AR: \(error.localizedDescription)" }

        } catch {
            errorMessage = "3D: \(error.localizedDescription)"
        }
    }

    func generateARUSDZ(from image: UIImage) async {
        guard !isBusy else { return }
        if usdzURL != nil { return }
        if let modelURL {
            isBusy = true
            errorMessage = nil
            progressText = "نحوّل المجسم المحفوظ إلى USDZ…"
            defer { isBusy = false; progressText = "" }
            do { usdzURL = try await USDZConverter.convertToUSDZ(modelURL) }
            catch { errorMessage = "AR: \(error.localizedDescription)" }
        } else {
            await generate3D(from: image, textured: true)
        }
    }

    private func hunyuanArguments(file: GradioFileData) -> [String: GradioValue] {
        [
            "caption": .null, "image": .file(file), "input_image": .file(file),
            "mv_image_front": .null, "mv_image_back": .null,
            "mv_image_left": .null, "mv_image_right": .null,
            "steps": .number(30), "num_inference_steps": .number(30),
            "guidance_scale": .number(5), "seed": .number(42),
            "octree_resolution": .number(256), "check_box_rembg": .bool(true),
            "num_chunks": .number(8000), "randomize_seed": .bool(true)
        ]
    }
}
