import Foundation

final class HuggingFaceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!

    // Provider-pinned models first so the app does not depend on the user's
    // auto-provider preference. If one provider is unavailable, we retry.
    private let visionModels = [
        "zai-org/GLM-5.3-Flash:baseten",
        "deepseek-ai/DeepSeek-V4-Flash-Vision-Exp:deepinfra",
        "deepseek-ai/DeepSeek-V4-Flash-Vision-Exp:fireworks-ai"
    ]

    private let personaModels = [
        "Qwen/Qwen3.8-27B:ovhcloud",
        "Qwen/Qwen3.8-27B:deepinfra",
        "zai-org/GLM-5.3-Flash:baseten"
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
            case .parse(let message):
                return "فشل فهم نتيجة الذكاء الاصطناعي: \(message)"
            case .noAvailableProvider:
                return "تعذّر الاتصال بأي مزوّد ذكاء اصطناعي متاح حاليًا. جرّب بعد قليل أو تأكد أن مفتاح Hugging Face يسمح باستخدام Inference Providers."
            }
        }
    }

    func diagnosePlant(imageData: Data) async throws -> PlantDiagnosis {
        let base64 = imageData.base64EncodedString()
        let schemaInstruction = """
        افحص صورة النبتة كخبير عناية بالنباتات المنزلية. لا تدّعي يقينًا غير موجود. أعد JSON فقط دون Markdown بهذا الشكل:
        {"plantName":"","scientificName":null,"healthStatus":"","likelyIssue":"","confidence":0,"urgency":"low|medium|high","visualEvidence":[""],"careSteps":[""],"warning":null}
        confidence رقم من 0 إلى 100. اكتب الإجابات بالعربية، وأبقِ الاسم العلمي باللاتينية عند معرفته. إذا لم تتأكد من النوع فقل نبات منزلي غير محدد. لا تشخّص مرضًا فطريًا أو آفة إلا إذا كانت العلامات البصرية تدعمه، واذكر أن التشخيص من الصورة تقديري.
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": schemaInstruction],
            ["role": "user", "content": [
                ["type": "text", "text": "حلّل حالة هذه النبتة وحدد النوع والمشكلة المحتملة وخطوات العناية."],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]]
        ]

        let text = try await performWithFallback(
            models: visionModels,
            messages: messages,
            temperature: 0.15,
            maxTokens: 900
        )
        return try decodeJSON(PlantDiagnosis.self, from: text)
    }

    func generatePersona(for diagnosis: PlantDiagnosis) async throws -> PlantPersonaMessage {
        let diagnosisData = try JSONEncoder().encode(diagnosis)
        let diagnosisJSON = String(data: diagnosisData, encoding: .utf8) ?? "{}"

        let system = """
        أنت كاتب شخصية تطبيق عربي سعودي يجعل النبتة تتحدث لصاحبها. اكتب بأسلوب طريف وعاطفي وخفيف، بدون تهويل أو معلومات تناقض التشخيص. الرسالة قصيرة وممتعة وقابلة للنطق. أعد JSON فقط دون Markdown بالشكل:
        {"mood":"","title":"","message":"","shortAction":"","voiceRate":0.47,"voicePitch":1.05}
        mood كلمة أو كلمتان مثل عطشان، متضايق، مرتاح، مصدوم. title عنوان قصير. message من 2 إلى 4 جمل. shortAction إجراء واحد واضح. voiceRate بين 0.40 و0.55 وvoicePitch بين 0.75 و1.35.
        """
        let user = "هذا التشخيص التقني: \(diagnosisJSON)\nحوّله إلى شخصية النبتة ورسالتها لصاحبها."

        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]

        let text = try await performWithFallback(
            models: personaModels,
            messages: messages,
            temperature: 0.78,
            maxTokens: 500
        )
        return try decodeJSON(PlantPersonaMessage.self, from: text)
    }

    private func performWithFallback(
        models: [String],
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        var lastUsefulError: Error?

        for model in models {
            let body: [String: Any] = [
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": maxTokens
            ]

            do {
                return try await perform(body: body)
            } catch HFError.server(let message) {
                lastUsefulError = HFError.server(message)
                if shouldTryNextProvider(message) { continue }
                throw HFError.server(friendlyServerMessage(message))
            } catch {
                lastUsefulError = error
                continue
            }
        }

        if let hf = lastUsefulError as? HFError {
            if case .server = hf { throw HFError.noAvailableProvider }
            throw hf
        }
        throw HFError.noAvailableProvider
    }

    private func perform(body: [String: Any]) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else {
            throw HFError.missingToken
        }

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
        if let content = message["content"] as? [[String: Any]] {
            let pieces = content.compactMap { $0["text"] as? String }
            if !pieces.isEmpty { return pieces.joined(separator: "\n") }
        }
        throw HFError.invalidResponse
    }

    private func shouldTryNextProvider(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("not supported by any provider")
            || m.contains("provider")
            || m.contains("unavailable")
            || m.contains("model_not_found")
            || m.contains("not found")
            || m.contains("503")
            || m.contains("429")
    }

    private func friendlyServerMessage(_ raw: String) -> String {
        let m = raw.lowercased()
        if m.contains("unauthorized") || m.contains("401") || m.contains("invalid token") {
            return "مفتاح Hugging Face غير صالح أو لا يملك صلاحية Inference Providers. احفظ مفتاحًا صحيحًا من الإعدادات."
        }
        if m.contains("payment") || m.contains("credit") || m.contains("402") {
            return "حساب Hugging Face يحتاج رصيدًا أو صلاحية لاستخدام مزوّد الذكاء الاصطناعي الحالي."
        }
        return "تعذّر إكمال التحليل من خدمة الذكاء الاصطناعي. جرّب مرة أخرى بعد قليل."
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else {
            throw HFError.parse(cleaned)
        }
        let json = String(cleaned[first...last])
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw HFError.parse(error.localizedDescription)
        }
    }
}
