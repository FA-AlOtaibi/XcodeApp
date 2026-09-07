import Foundation

final class HuggingFaceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let visionModels = [
        "zai-org/GLM-5.3-Flash:baseten",
        "Qwen/Qwen3-VL-8B-Instruct:fireworks-ai"
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
                return "ما فيه مزوّد متاح للتحليل الآن. تأكد أن مفتاح Hugging Face يسمح باستخدام Inference Providers ثم جرّب مرة أخرى."
            }
        }
    }

    func analyzeImage(imageData: Data) async throws -> VisualAnalysis {
        let base64 = imageData.base64EncodedString()
        let system = """
        أنت محلل بصري عام. حلّل أي صورة يرسلها المستخدم: جسم، منتج، جهاز، سيارة، أداة، طعام، مبنى، حيوان، نبات، مشهد أو أي شيء آخر.
        مهمتك أن تشرح ما يظهر ببساطة وبدقة، بدون اختلاق تفاصيل غير مرئية.
        أعد JSON فقط بلا Markdown بهذا الشكل:
        {"title":"","category":"","summary":"","confidence":0,"keyFacts":[""],"visibleDetails":[""],"howItWorksOrUsed":[""],"cautions":[""],"uncertainty":null}

        القواعد:
        - اكتب بالعربية السهلة.
        - title اسم العنصر أو وصف مختصر جدًا للمشهد.
        - category فئة عامة مثل: إلكترونيات، سيارة، أداة، طعام، نبات، مبنى، حيوان، ملابس، مشهد، غير ذلك.
        - summary شرح مبسط من سطرين إلى أربعة.
        - confidence من 0 إلى 100 بناءً على وضوح الصورة.
        - keyFacts حقائق مفيدة ومختصرة مرتبطة بما تم التعرف عليه.
        - visibleDetails فقط ما يمكن ملاحظته بصريًا في الصورة.
        - howItWorksOrUsed يشرح الاستخدام أو الوظيفة أو طريقة العمل عندما يكون ذلك مناسبًا.
        - cautions للمخاطر أو التنبيهات العملية فقط عند الحاجة، وإلا أعد مصفوفة فارغة.
        - uncertainty اذكر فيه ما لم تستطع تأكيده، وإلا null.
        - إذا لم تستطع التعرف على العنصر تحديدًا، صفه بدقة ولا تخمن علامة تجارية أو موديلًا.
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": [
                ["type": "text", "text": "عرّف لي ما في هذه الصورة واشرحه ببساطة ثم أعطني التفاصيل المفيدة التي تستطيع استنتاجها بصريًا."],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]]
        ]

        let text = try await performWithFallback(models: visionModels, messages: messages, temperature: 0.12, maxTokens: 1100)
        return try decodeJSON(VisualAnalysis.self, from: text)
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
                throw HFError.server("مفتاح Hugging Face غير صالح أو ناقص الصلاحيات. استخدم Fine-grained token بصلاحية Inference Providers.")
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
