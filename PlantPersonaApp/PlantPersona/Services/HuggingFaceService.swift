import Foundation

final class HuggingFaceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let visionModel = "Qwen/Qwen2.5-VL-3B-Instruct:fastest"
    private let personaModel = "Qwen/Qwen2.5-7B-Instruct:fastest"

    enum HFError: LocalizedError {
        case missingToken
        case invalidResponse
        case server(String)
        case parse(String)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "أضف مفتاح Hugging Face من الإعدادات أولًا."
            case .invalidResponse:
                return "وصل رد غير صالح من Hugging Face."
            case .server(let message):
                return message
            case .parse(let message):
                return "فشل فهم نتيجة الذكاء الاصطناعي: \(message)"
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

        let body: [String: Any] = [
            "model": visionModel,
            "messages": [
                ["role": "system", "content": schemaInstruction],
                ["role": "user", "content": [
                    ["type": "text", "text": "حلّل حالة هذه النبتة وحدد النوع والمشكلة المحتملة وخطوات العناية."],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                ]]
            ],
            "temperature": 0.15,
            "max_tokens": 900
        ]

        let text = try await perform(body: body)
        return try decodeJSON(PlantDiagnosis.self, from: text)
    }

    func generatePersona(for diagnosis: PlantDiagnosis) async throws -> PlantPersonaMessage {
        let diagnosisData = try JSONEncoder().encode(diagnosis)
        let diagnosisJSON = String(data: diagnosisData, encoding: .utf8) ?? "{}"

        let system = """
        أنت كاتب شخصية تطبيق عربي سعودي يجعل النبتة تتحدث لصاحبها. اكتب بأسلوب طريف وعاطفي وخفيف، بدون تهويل طبي أو معلومات تناقض التشخيص. الرسالة يجب أن تكون قصيرة وممتعة وقابلة للنطق. أعد JSON فقط دون Markdown بالشكل:
        {"mood":"","title":"","message":"","shortAction":"","voiceRate":0.47,"voicePitch":1.05}
        mood كلمة أو كلمتان مثل عطشان، متضايق، مرتاح، مصدوم. title عنوان قصير. message من 2 إلى 4 جمل. shortAction إجراء واحد واضح. voiceRate بين 0.40 و0.55 وvoicePitch بين 0.75 و1.35.
        """
        let user = "هذا التشخيص التقني: \(diagnosisJSON)\nحوّله إلى شخصية النبتة ورسالتها لصاحبها."

        let body: [String: Any] = [
            "model": personaModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.8,
            "max_tokens": 500
        ]

        let text = try await perform(body: body)
        return try decodeJSON(PlantPersonaMessage.self, from: text)
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
                ?? "Hugging Face HTTP \(http.statusCode)"
            throw HFError.server(message)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw HFError.invalidResponse
        }
        return content
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
