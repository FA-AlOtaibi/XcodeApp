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
        case providerRefusal(String)

        var errorDescription: String? {
            switch self {
            case .missingToken: return "أضف مفتاح Hugging Face من الإعدادات أولًا."
            case .invalidResponse: return "وصل رد غير صالح من خدمة الذكاء الاصطناعي. جرّب مرة أخرى."
            case .server(let message): return message
            case .parse: return "وصل رد من النموذج لكن تعذر ترتيبه. جرّب مرة أخرى."
            case .noAvailableProvider: return "ما فيه مزوّد متاح للتحليل الآن. تأكد أن مفتاح Hugging Face يسمح باستخدام Inference Providers ثم جرّب مرة أخرى."
            case .providerRefusal(let reason): return "مزود الذكاء الاصطناعي رفض تحليل هذا المحتوى بسبب سياسته. \(reason)"
            }
        }
    }

    func analyzeImage(imageData: Data, obdContext: String? = nil) async throws -> VisualAnalysis {
        let content: [[String: Any]] = [
            ["type": "text", "text": userInstruction(obdContext: obdContext, videoSound: nil)],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]
        ]
        return try await analyzeContent(content)
    }

    func analyzeVideoFrames(_ frames: [Data], sound: MediaSoundProfile?, obdContext: String? = nil) async throws -> VisualAnalysis {
        var content: [[String: Any]] = [[
            "type": "text",
            "text": userInstruction(obdContext: obdContext, videoSound: sound)
        ]]
        for frame in frames.prefix(8) {
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(frame.base64EncodedString())"]])
        }
        return try await analyzeContent(content)
    }

    private func analyzeContent(_ content: [[String: Any]]) async throws -> VisualAnalysis {
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": content]
        ]
        let raw = try await performWithFallback(models: visionModels, messages: messages, temperature: 0.10, maxTokens: 1800)

        if isProviderRefusal(raw) {
            throw HFError.providerRefusal(shortRefusalReason(raw))
        }

        if let direct = try? decodeJSON(VisualAnalysis.self, from: raw) {
            return direct
        }

        // بعض النماذج تعطي شرحًا صحيحًا لكن بصيغة JSON غير مكتملة أو مع نص زائد.
        // نطلب منها مرة واحدة إعادة تنسيق نفس الرد دون إعادة تحليل الصورة أو إضافة حقائق جديدة.
        if let repaired = try? await repairToVisualAnalysis(raw) {
            return repaired
        }

        // آخر fallback: لا نرمي نتيجة مفيدة فقط لأن الصيغة لم تطابق الـschema.
        let cleaned = readableFallback(raw)
        guard !cleaned.isEmpty else { throw HFError.parse(raw) }
        return VisualAnalysis(
            title: "نتيجة التحليل",
            category: "تحليل عام",
            summary: cleaned,
            confidence: 45,
            keyFacts: [],
            visibleDetails: [],
            howItWorksOrUsed: [],
            cautions: [],
            uncertainty: "الرد وصل كنص غير منظم، لذلك بعض الأقسام التفصيلية غير متاحة في هذه المحاولة.",
            automotive: nil
        )
    }

    private func repairToVisualAnalysis(_ raw: String) async throws -> VisualAnalysis {
        let repairSystem = """
        أنت مُنسّق بيانات فقط. لا تستنتج أي معلومة جديدة ولا تغيّر معنى النص.
        حوّل الرد المرفق إلى JSON صالح فقط بهذا الشكل:
        {"title":"","category":"","summary":"","confidence":0,"keyFacts":[],"visibleDetails":[],"howItWorksOrUsed":[],"cautions":[],"uncertainty":null,"automotive":null}
        إذا كانت معلومة غير موجودة استخدم قيمة فارغة مناسبة. confidence رقم صحيح من 0 إلى 100.
        """
        let repairMessages: [[String: Any]] = [
            ["role": "system", "content": repairSystem],
            ["role": "user", "content": "أعد تنسيق هذا الرد فقط:\n\(String(raw.prefix(7000)))"]
        ]
        let repaired = try await performWithFallback(models: visionModels, messages: repairMessages, temperature: 0.0, maxTokens: 1500)
        if isProviderRefusal(repaired) { throw HFError.providerRefusal(shortRefusalReason(repaired)) }
        return try decodeJSON(VisualAnalysis.self, from: repaired)
    }

    private var systemPrompt: String {
        """
        أنت محرك عَيْن لتحليل الصور والفيديو، ومتخصص أيضًا في تشخيص أعطال السيارات بطريقة عملية محافظة.
        حلّل أي جسم أو مشهد بدقة وبدون اختلاق علامة أو موديل غير ظاهر. إذا كان المحتوى متعلقًا بسيارة أو جزء سيارة أو أعراض سيارة، فعّل قسم automotive.

        أعد JSON فقط بلا Markdown بهذا الشكل تمامًا:
        {"title":"","category":"","summary":"","confidence":0,"keyFacts":[""],"visibleDetails":[""],"howItWorksOrUsed":[""],"cautions":[""],"uncertainty":null,"automotive":null}

        وعند السيارات اجعل automotive بهذا الشكل:
        {"isVehicleRelated":true,"probableSystem":"","severity":"low|medium|high|critical","canDrive":"نعم|بحذر|لا","symptoms":[""],"likelyCauses":[{"cause":"","probability":0,"reasoning":""}],"checks":[""],"fixes":[""],"dtcHints":["P0000"],"mechanicNote":""}

        قواعد السيارات:
        - لا تقل إن عطلًا مؤكّد من صورة/فيديو/صوت فقط. استخدم "الأرجح" واذكر حدود الاستنتاج.
        - رتب likelyCauses من الأعلى للأقل واحرص أن مجموع الاحتمالات تقريبي وليس تشخيصًا نهائيًا.
        - checks يجب أن تبدأ بفحوصات بسيطة وقليلة التكلفة قبل اقتراح تبديل قطع.
        - fixes حلول عملية مرتبطة بالأسباب فقط، ولا تقترح شراء قطعة قبل اختبارها إن أمكن.
        - dtcHints أكواد OBD المحتملة فقط إذا كان الربط منطقيًا، ولا تخترع كودًا غير قياسي.
        - إذا ظهرت مؤشرات سلامة مثل حرارة شديدة، ضغط زيت، فرامل، تسريب وقود، دخان كثيف أو صوت طرق قوي: severity critical وcanDrive "لا".
        - بيانات OBD إن وُجدت أقوى من التخمين البصري؛ اربط الأكواد والقراءات بالأعراض.
        - مؤشرات الصوت المستخرجة من الفيديو تقريبية وليست بديلًا عن سماع ميكانيكي أو قياسات اهتزاز احترافية.

        القواعد العامة:
        - العربية سهلة وواضحة.
        - confidence من 0 إلى 100.
        - visibleDetails ما شوهد فعليًا فقط.
        - cautions للمخاطر العملية، وإلا [] .
        - uncertainty اذكر ما لم يمكن تأكيده، وإلا null.
        """
    }

    private func userInstruction(obdContext: String?, videoSound: MediaSoundProfile?) -> String {
        var text = "حلّل المحتوى، عرّف ما يظهر واشرحه ببساطة مع التفاصيل المفيدة. إذا له علاقة بسيارة فحوّل التحليل إلى تشخيص أعطال مرتب: الأعراض، الأسباب المرجحة، كيف أفحصها، والحلول."
        if let s = videoSound {
            text += "\nمؤشرات الصوت المستخرجة من الفيديو: مدة \(String(format: "%.1f", s.durationSeconds)) ثانية، RMS=\(String(format: "%.4f", s.rms))، Peak=\(String(format: "%.4f", s.peak))، ZeroCrossing=\(String(format: "%.4f", s.zeroCrossingRate))"
            if let hz = s.dominantPulseHz { text += "، نبض دوري تقريبي=\(String(format: "%.2f", hz))Hz" }
            text += ". \(s.note)"
        }
        if let obdContext, !obdContext.isEmpty {
            text += "\nبيانات OBD الفعلية من السيارة:\n\(obdContext)"
        }
        return text
    }

    private func performWithFallback(models: [String], messages: [[String: Any]], temperature: Double, maxTokens: Int) async throws -> String {
        var lastMessage: String?
        for model in models {
            do { return try await perform(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens) }
            catch HFError.server(let message) { lastMessage = message; continue }
            catch HFError.providerRefusal { throw errorForRefusal(lastMessage) }
            catch { continue }
        }
        if let lastMessage {
            let lower = lastMessage.lowercased()
            if lower.contains("401") || lower.contains("unauthorized") || lower.contains("token") {
                throw HFError.server("مفتاح Hugging Face غير صالح أو ناقص الصلاحيات. استخدم Fine-grained token بصلاحية Inference Providers.")
            }
        }
        throw HFError.noAvailableProvider
    }

    private func errorForRefusal(_ message: String?) -> HFError {
        HFError.providerRefusal(message.map(shortRefusalReason) ?? "")
    }

    private func perform(model: String, messages: [[String: Any]], temperature: Double, maxTokens: Int) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else { throw HFError.missingToken }
        let body: [String: Any] = ["model": model, "messages": messages, "temperature": temperature, "max_tokens": maxTokens]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HFError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (payload?["error"] as? [String: Any])?["message"] as? String ?? payload?["error"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if isProviderRefusal(message) { throw HFError.providerRefusal(shortRefusalReason(message)) }
            throw HFError.server(message)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = root["choices"] as? [[String: Any]], let first = choices.first, let message = first["message"] as? [String: Any] else { throw HFError.invalidResponse }
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
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }

        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else { throw HFError.parse(cleaned) }
        let candidate = String(cleaned[first...last])
        do { return try JSONDecoder().decode(T.self, from: Data(candidate.utf8)) }
        catch { throw HFError.parse(error.localizedDescription) }
    }

    private func readableFallback(_ raw: String) -> String {
        raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1800)
            .description
    }

    private func isProviderRefusal(_ raw: String) -> Bool {
        let s = raw.lowercased()
        let markers = [
            "cannot assist", "can't assist", "cannot analyze", "can't analyze", "unable to analyze",
            "policy", "safety policy", "sexual content", "explicit content", "nudity", "nsfw",
            "لا أستطيع تحليل", "لا يمكنني تحليل", "لا أستطيع المساعدة", "محتوى جنسي", "محتوى صريح", "سياسة المحتوى"
        ]
        return markers.contains { s.contains($0) }
    }

    private func shortRefusalReason(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        return String(text.prefix(220))
    }
}
