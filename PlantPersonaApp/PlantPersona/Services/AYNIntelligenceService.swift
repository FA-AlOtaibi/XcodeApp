import Foundation

final class AYNIntelligenceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let models = ["zai-org/GLM-5.3-Flash:baseten", "Qwen/Qwen3.8-27B:deepinfra"]

    enum ServiceError: LocalizedError {
        case missingToken, invalidResponse, unavailable
        var errorDescription: String? {
            switch self {
            case .missingToken: return "أضف مفتاح Hugging Face من الإعدادات أولًا."
            case .invalidResponse: return "تعذر قراءة رد الذكاء الاصطناعي."
            case .unavailable: return "تعذر الوصول إلى نموذج مناسب الآن."
            }
        }
    }

    func ask(_ question: String, context: String? = nil) async throws -> String {
        var user = question
        if let context, !context.isEmpty { user += "\n\nالسياق الحالي من عَيْن:\n\(context)" }
        return try await chat(system: "أنت عَيْن، مساعد بصري وتقني عملي. أجب بالعربية السهلة، اختصر الهبد، ميّز بين المؤكد والمحتمل، وابدأ بخطوات الفحص الأبسط قبل اقتراح تغيير قطع أو شراء شيء.", user: user)
    }

    func compare(images: [Data], prompt: String) async throws -> String {
        guard !images.isEmpty else { return "أضف صورًا للمقارنة أولًا." }
        var content: [[String: Any]] = [["type":"text","text":prompt + "\nقارن بدقة بين الصور بالترتيب. اذكر ما تغير، ما بقي ثابتًا، ومدى ثقتك. لا تخترع تغيرات غير ظاهرة."]]
        for image in images.prefix(6) {
            content.append(["type":"image_url","image_url":["url":"data:image/jpeg;base64,\(image.base64EncodedString())"]])
        }
        let messages: [[String: Any]] = [
            ["role":"system","content":"أنت محلل مقارنة بصري. اكتب بالعربية بنقاط واضحة مع: الخلاصة، التغيرات، الأشياء الثابتة، ما يحتاج متابعة."],
            ["role":"user","content":content]
        ]
        return try await perform(messages: messages, maxTokens: 1400)
    }

    func reviewTechnician(statement: String, analysis: VisualAnalysis?, obd: String?) async throws -> String {
        var context = "كلام الفني: \(statement)"
        if let analysis { context += "\nتحليل عَيْن السابق: \(analysis.title) — \(analysis.summary)" }
        if let obd, !obd.isEmpty { context += "\nبيانات OBD:\n\(obd)" }
        return try await chat(system: "راجع كلام الفني كخبير صيانة محافظ. لا تقل إن الفني مخطئ بلا دليل. اذكر: ما المنطقي، ما يحتاج إثبات، الاختبارات التي يجب طلبها قبل تغيير القطع، وما هي العلامات التي تجعل الإصلاح عاجلًا.", user: context)
    }

    func guidedNextStep(current: VisualAnalysis?, mode: String) async throws -> String {
        let context = current.map { "العنصر: \($0.title)\nالملخص: \($0.summary)\nعدم اليقين: \($0.uncertainty ?? "لا يوجد")" } ?? "لا توجد نتيجة سابقة."
        return try await chat(system: "أنت مساعد فحص بصري تفاعلي. أعط المستخدم خطوة تصوير واحدة فقط تساعد أكثر في تأكيد التشخيص. اجعلها قصيرة جدًا وآمنة.", user: "الوضع: \(mode)\n\(context)")
    }

    private func chat(system: String, user: String) async throws -> String {
        try await perform(messages: [["role":"system","content":system],["role":"user","content":user]], maxTokens: 1300)
    }

    private func perform(messages: [[String: Any]], maxTokens: Int) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else { throw ServiceError.missingToken }
        for model in models {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["model":model,"messages":messages,"temperature":0.15,"max_tokens":maxTokens])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = root["choices"] as? [[String: Any]], let first = choices.first, let message = first["message"] as? [String: Any] else { continue }
                if let text = message["content"] as? String, !text.isEmpty { return text }
                if let parts = message["content"] as? [[String: Any]] {
                    let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if !text.isEmpty { return text }
                }
            } catch { continue }
        }
        throw ServiceError.unavailable
    }
}
