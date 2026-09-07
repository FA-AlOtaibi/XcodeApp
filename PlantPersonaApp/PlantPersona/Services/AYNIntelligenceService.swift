import Foundation

final class AYNIntelligenceService {
    private let endpoint = URL(string: "https://router.huggingface.co/v1/chat/completions")!
    private let models = ["zai-org/GLM-5.3-Flash:baseten", "Qwen/Qwen3.8-27B:deepinfra"]

    enum ServiceError: LocalizedError {
        case missingToken, invalidResponse, unavailable
        var errorDescription: String? {
            switch self {
            case .missingToken: return "أضف مفتاح Hugging Face من الإعدادات."
            case .invalidResponse: return "تعذر قراءة الرد."
            case .unavailable: return "الخدمة غير متاحة الآن."
            }
        }
    }

    func ask(_ question: String, context: String? = nil) async throws -> String {
        var user = question
        if let context, !context.isEmpty {
            user += "\n\nسياق اختياري من آخر تحليل، استخدمه فقط إذا كان مرتبطًا بالسؤال:\n\(context)"
        }
        return try await chat(
            system: """
            أنت عَيْن، مساعد عام وعملي. يحق للمستخدم أن يسألك أي سؤال عادي حتى بدون صورة.
            أجب مباشرة بالعربية السهلة. لا تبدأ بطلب صورة أو أسئلة توضيحية إلا إذا كانت ضرورية جدًا للإجابة.
            لا تكرر الفكرة نفسها بصيغ مختلفة. اجعل الرد مختصرًا افتراضيًا، وميّز بوضوح بين المعلومة المؤكدة والتخمين.
            إذا كان السؤال عن سيارة، ابدأ بالفحص الأبسط والأقل تكلفة قبل اقتراح تغيير قطع.
            """,
            user: user,
            maxTokens: 850
        )
    }

    func compare(images: [Data], prompt: String) async throws -> String {
        guard images.count >= 2 else { return "اختر صورتين على الأقل." }
        var content: [[String: Any]] = [[
            "type":"text",
            "text":prompt + "\nاكتب: الخلاصة، التغيرات المهمة فقط، وما يحتاج متابعة. لا تكرر ولا تخترع اختلافات غير ظاهرة."
        ]]
        for image in images.prefix(6) {
            content.append(["type":"image_url","image_url":["url":"data:image/jpeg;base64,\(image.base64EncodedString())"]])
        }
        return try await perform(messages: [
            ["role":"system","content":"أنت محلل مقارنة بصري دقيق ومختصر."],
            ["role":"user","content":content]
        ], maxTokens: 900)
    }

    func reviewTechnician(statement: String, analysis: VisualAnalysis?, obd: String?) async throws -> String {
        var context = "كلام الفني: \(statement)"
        if let analysis { context += "\nتحليل سابق: \(analysis.title) — \(analysis.summary)" }
        if let obd, !obd.isEmpty { context += "\nOBD:\n\(obd)" }
        return try await chat(
            system: "راجع كلام الفني بحياد واختصار. أعط: هل الكلام منطقي، ما الذي يحتاج إثبات، وما الاختبار الذي يسبق تغيير القطعة. لا تتهم الفني ولا تكرر الكلام.",
            user: context,
            maxTokens: 750
        )
    }

    func guidedNextStep(current: VisualAnalysis?, mode: String) async throws -> String {
        guard let current else { return "" }
        let context = "العنصر: \(current.title)\nالملخص: \(current.summary)\nعدم اليقين: \(current.uncertainty ?? "لا يوجد")"
        return try await chat(
            system: "أعط خطوة تصوير واحدة فقط تساعد في زيادة دقة الفحص. جملة قصيرة، بدون مقدمة وبدون أكثر من سؤال واحد.",
            user: "الوضع: \(mode)\n\(context)",
            maxTokens: 180
        )
    }

    private func chat(system: String, user: String, maxTokens: Int) async throws -> String {
        try await perform(messages: [["role":"system","content":system],["role":"user","content":user]], maxTokens: maxTokens)
    }

    private func perform(messages: [[String: Any]], maxTokens: Int) async throws -> String {
        guard let token = KeychainStore.shared.loadToken(), !token.isEmpty else { throw ServiceError.missingToken }
        for model in models {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 60
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model":model,
                    "messages":messages,
                    "temperature":0.12,
                    "max_tokens":maxTokens
                ])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = root["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any] else { continue }
                if let text = message["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let parts = message["content"] as? [[String: Any]] {
                    let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { return text }
                }
            } catch { continue }
        }
        throw ServiceError.unavailable
    }
}
