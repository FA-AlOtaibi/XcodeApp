import Foundation

final class HuggingFaceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let visionModels = [
        "zai-org/GLM-5.3-Flash:baseten",
        "Qwen/Qwen3-VL-8B-Instruct:fireworks-ai"
    ]

    enum HFError: LocalizedError {
        case missingToken, invalidResponse, noAvailableProvider, parse
        case server(String), providerRefusal(String)

        var errorDescription: String? {
            switch self {
            case .missingToken: return "أضف مفتاح Hugging Face من الإعدادات."
            case .invalidResponse: return "تعذر قراءة نتيجة التحليل. جرّب مرة ثانية."
            case .noAvailableProvider: return "خدمة التحليل غير متاحة الآن."
            case .parse: return "وصلت نتيجة غير مكتملة. جرّب مرة ثانية."
            case .server(let message): return message
            case .providerRefusal(let reason): return "تعذر تحليل هذا المحتوى لدى المزود. \(reason)"
            }
        }
    }

    func analyzeImage(imageData: Data, obdContext: String? = nil) async throws -> VisualAnalysis {
        let content: [[String: Any]] = [
            ["type": "text", "text": instruction(obdContext: obdContext, sound: nil)],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]
        ]
        return try await analyze(content)
    }

    func analyzeVideoFrames(_ frames: [Data], sound: MediaSoundProfile?, obdContext: String? = nil) async throws -> VisualAnalysis {
        var content: [[String: Any]] = [["type": "text", "text": instruction(obdContext: obdContext, sound: sound)]]
        for frame in frames.prefix(6) {
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(frame.base64EncodedString())"]])
        }
        return try await analyze(content)
    }

    private func analyze(_ content: [[String: Any]]) async throws -> VisualAnalysis {
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": content]
        ]
        let raw = try await performWithFallback(messages: messages, maxTokens: 1500)
        if isRefusal(raw) { throw HFError.providerRefusal(shortReason(raw)) }
        if let result = try? decode(raw) { return result }
        if let repaired = try? await repair(raw), let result = try? decode(repaired) { return result }

        let readable = cleanText(raw)
        guard !readable.isEmpty else { throw HFError.parse }
        return VisualAnalysis(
            title: "نتيجة التحليل",
            category: "عام",
            summary: readable,
            confidence: 40,
            keyFacts: [],
            visibleDetails: [],
            howItWorksOrUsed: [],
            cautions: [],
            uncertainty: "النتيجة وصلت كنص عام.",
            automotive: nil,
            geo: nil
        )
    }

    private var systemPrompt: String {
        """
        أنت محرك عَيْن لفهم الصور والفيديو. أجب بالعربية المختصرة والمفيدة ولا تكرر نفس المعلومة في أكثر من قسم.
        أعد JSON فقط، بدون Markdown:
        {
          "title":"",
          "category":"",
          "summary":"",
          "confidence":0,
          "keyFacts":[],
          "visibleDetails":[],
          "howItWorksOrUsed":[],
          "cautions":[],
          "uncertainty":null,
          "automotive":null,
          "geo":null
        }

        قواعد عامة:
        - summary من سطر إلى ثلاثة أسطر فقط.
        - لا تكرر الملخص داخل keyFacts أو visibleDetails.
        - اعرض فقط التفاصيل المفيدة فعلًا.
        - لا تخترع ماركة أو موديل أو مكانًا غير مدعوم بأدلة.

        تحديد المكان بصريًا:
        - حاول تقدير المكان فقط إذا توجد قرائن مفيدة مثل لافتات، لغة، لوحات طرق، معالم، طراز عمراني، تضاريس، ساحل، نباتات، أرقام طرق أو أسماء متاجر.
        - geo = {"country":null,"city":null,"area":null,"landmark":null,"confidence":0,"evidence":[],"latitude":null,"longitude":null}
        - إن لم توجد قرائن كافية اجعل geo=null.
        - لا تعط إحداثيات إلا لمعْلم واضح جدًا أو مكان يمكن تمييزه بثقة عالية. لا تخمّن عنوانًا خاصًا أو موقع منزل.
        - evidence يشرح باختصار القرائن المرئية التي بُني عليها التقدير.

        السيارات:
        إذا كان المحتوى متعلقًا بسيارة، automotive = {
          "isVehicleRelated":true,
          "probableSystem":"",
          "severity":"low|medium|high|critical",
          "canDrive":"نعم|بحذر|لا",
          "symptoms":[],
          "likelyCauses":[{"cause":"","probability":0,"reasoning":""}],
          "checks":[],
          "fixes":[],
          "dtcHints":[],
          "mechanicNote":""
        }
        ابدأ بالفحوصات الأبسط والأرخص. لا تعتبر العطل مؤكدًا من صورة أو صوت فقط. بيانات OBD أقوى من التخمين البصري.
        """
    }

    private func instruction(obdContext: String?, sound: MediaSoundProfile?) -> String {
        var text = "حلّل المحتوى مباشرة. عرّف ما يظهر، اشرح أهم ما يفيد المستخدم، وحاول تقدير المكان بصريًا إذا توجد قرائن حقيقية."
        if let sound {
            text += "\nصوت الفيديو: RMS \(String(format: "%.3f", sound.rms)), Peak \(String(format: "%.3f", sound.peak)), ZCR \(String(format: "%.3f", sound.zeroCrossingRate))."
            if let hz = sound.dominantPulseHz { text += " نبض تقريبي \(String(format: "%.1f", hz))Hz." }
        }
        if let obdContext, !obdContext.isEmpty { text += "\nOBD:\n\(obdContext)" }
        return text
    }

    private func repair(_ raw: String) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": "حوّل النص التالي فقط إلى JSON صالح مطابق لحقول VisualAnalysis، بدون إضافة معلومات جديدة. استخدم مصفوفات فارغة وnull عند غياب المعلومة."],
            ["role": "user", "content": String(raw.prefix(6500))]
        ]
        return try await performWithFallback(messages: messages, maxTokens: 1100)
    }

    private func performWithFallback(messages: [[String: Any]], maxTokens: Int) async throws -> String {
        var lastError: String?
        for model in visionModels {
            do { return try await perform(model: model, messages: messages, maxTokens: maxTokens) }
            catch HFError.providerRefusal { throw HFError.providerRefusal("") }
            catch HFError.server(let message) { lastError = message }
            catch { continue }
        }
        if let lastError, lastError.lowercased().contains("token") { throw HFError.server("مفتاح Hugging Face غير صالح أو ناقص الصلاحيات.") }
        throw HFError.noAvailableProvider
    }

    private func perform(model: String, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else { throw HFError.missingToken }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages,
            "temperature": 0.08,
            "max_tokens": maxTokens
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HFError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if isRefusal(text) { throw HFError.providerRefusal(shortReason(text)) }
            throw HFError.server(text.count > 240 ? String(text.prefix(240)) : text)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { throw HFError.invalidResponse }
        if let text = message["content"] as? String, !text.isEmpty { return text }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        throw HFError.invalidResponse
    }

    private func decode(_ raw: String) throws -> VisualAnalysis {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = cleaned.data(using: .utf8), let result = try? JSONDecoder().decode(VisualAnalysis.self, from: data) { return result }
        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else { throw HFError.parse }
        return try JSONDecoder().decode(VisualAnalysis.self, from: Data(cleaned[first...last].utf8))
    }

    private func cleanText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isRefusal(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.contains("content policy") || s.contains("safety policy") || s.contains("cannot assist") || s.contains("can't assist")
    }

    private func shortReason(_ text: String) -> String {
        String(cleanText(text).prefix(180))
    }
}
