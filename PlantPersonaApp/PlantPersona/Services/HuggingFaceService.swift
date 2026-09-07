import Foundation

final class HuggingFaceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let visionModels = [
        "zai-org/GLM-5.3-Flash:baseten",
        "Qwen/Qwen3-VL-8B-Instruct:fireworks-ai"
    ]
    private let personaModels = [
        "zai-org/GLM-5.3-Flash:baseten",
        "Qwen/Qwen3.8-27B:deepinfra"
    ]

    enum HFError: LocalizedError {
        case missingToken
        case invalidResponse
        case server(String)
        case parse(String)
        case noAvailableProvider

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "أضف مفتاح Hugging Face من الإعدادات أولًا."
            case .invalidResponse:
                return "وصل رد غير صالح من خدمة الذكاء الاصطناعي. جرّب مرة أخرى."
            case .server(let message):
                return message
            case .parse:
                return "وصلت نتيجة غير مفهومة من النموذج. جرّب صورة أوضح."
            case .noAvailableProvider:
                return "ما فيه مزوّد متاح لهذا التحليل الآن. تأكد أن مفتاح Hugging Face يسمح باستخدام Inference Providers ثم جرّب مرة أخرى."
            }
        }
    }

    func diagnosePlant(imageData: Data) async throws -> PlantDiagnosis {
        let base64 = imageData.base64EncodedString()
        let system = """
        افحص صورة النبتة كخبير عناية بالنباتات المنزلية. أعد JSON فقط بلا Markdown:
        {"plantName":"","scientificName":null,"healthStatus":"","likelyIssue":"","confidence":0,"urgency":"low|medium|high","visualEvidence":[""],"careSteps":[""],"warning":null}
        اكتب بالعربية، confidence من 0 إلى 100، ولا تدّعي اليقين من صورة واحدة.
        """
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": [
                ["type": "text", "text": "حلّل هذه النبتة وحدد نوعها وحالتها والمشكلة المحتملة وخطوات العناية."],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]]
        ]
        let text = try await performWithFallback(models: visionModels, messages: messages, temperature: 0.15, maxTokens: 850)
        return try decodeJSON(PlantDiagnosis.self, from: text)
    }

    func generatePersona(for diagnosis: PlantDiagnosis) async throws -> PlantPersonaMessage {
        let data = try JSONEncoder().encode(diagnosis)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let system = """
        حوّل تشخيص النبتة إلى رسالة عربية سعودية خفيفة وطريفة على لسان النبتة. أعد JSON فقط:
        {"mood":"","title":"","message":"","shortAction":"","voiceRate":0.47,"voicePitch":1.05}
        لا تضف معلومات تخالف التشخيص. اجعل الرسالة قصيرة وواضحة.
        """
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": "التشخيص: \(json)"]
        ]
        let text = try await performWithFallback(models: personaModels, messages: messages, temperature: 0.75, maxTokens: 450)
        return try decodeJSON(PlantPersonaMessage.self, from: text)
    }

    private func performWithFallback(models: [String], messages: [[String: Any]], temperature: Double, maxTokens: Int) async throws -> String {
        var lastMessage: String?
        for model in models {
            do {
                return try await perform(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens)
            } catch HFError.server(let message) {
                lastMessage = message
                continue
            } catch {
                continue
            }
        }
        if let lastMessage {
            let lower = lastMessage.lowercased()
            if lower.contains("401") || lower.contains("unauthorized") || lower.contains("token") {
                throw HFError.server("مفتاح Hugging Face غير صالح أو ناقص الصلاحيات. أنشئ Fine-grained token بصلاحية Inference Providers.")
            }
        }
        throw HFError.noAvailableProvider
    }

    private func perform(model: String, messages: [[String: Any]], temperature: Double, maxTokens: Int) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else { throw HFError.missingToken }
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HFError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (payload?["error"] as? [String: Any])?["message"] as? String
                ?? payload?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw HFError.server(message)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw HFError.invalidResponse
        }
        if let content = message["content"] as? String { return content }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        throw HFError.invalidResponse
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else { throw HFError.parse(cleaned) }
        let json = String(cleaned[first...last])
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw HFError.parse(error.localizedDescription)
        }
    }
}
