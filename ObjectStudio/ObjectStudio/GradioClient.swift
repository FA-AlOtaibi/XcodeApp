import Foundation
import UIKit

struct GradioFileData: Codable {
    let path: String
    let url: String?
    let origName: String
    let meta: Meta

    struct Meta: Codable {
        let type: String
        enum CodingKeys: String, CodingKey { case type = "_type" }
    }

    enum CodingKeys: String, CodingKey {
        case path, url
        case origName = "orig_name"
        case meta
    }
}

enum GradioValue {
    case string(String), number(Double), bool(Bool), null, file(GradioFileData)

    var json: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .file(let file):
            var value: [String: Any] = [
                "path": file.path,
                "orig_name": file.origName,
                "meta": ["_type": "gradio.FileData"]
            ]
            if let url = file.url { value["url"] = url }
            return value
        }
    }
}

actor GradioClient {
    enum ClientError: LocalizedError {
        case badURL, invalidResponse, server(String), http(Int, String), noEventID, timedOut, missingOutput

        var errorDescription: String? {
            switch self {
            case .badURL: return "رابط Hugging Face غير صحيح."
            case .invalidResponse: return "استجابة Hugging Face غير مفهومة."
            case .server(let text): return text == "null" ? "توقفت خدمة GPU دون تفاصيل. تحقق من حصة الحساب وحالة الخدمة ثم أعد المحاولة." : text
            case .http(let code, let detail):
                switch code {
                case 401, 403: return "تعذر الوصول للخدمة (\(code)). تحقق من التوكن وصلاحيات حسابك."
                case 404: return "مسار الخدمة غير موجود (404). تحقق من رابط Space أو تغيّر واجهته. \(detail)"
                case 429: return "انتهت الحصة أو تجاوزت حد الطلبات. انتظر قبل إعادة المحاولة."
                case 503: return "الخدمة غير جاهزة أو في وضع السكون. حاول لاحقًا."
                default: return "HTTP \(code): \(detail)"
                }
            case .noEventID: return "لم يرجع السيرفر رقم العملية."
            case .timedOut: return "انتهى وقت الانتظار قبل اكتمال العملية."
            case .missingOutput: return "اكتملت العملية بدون ملف نتيجة."
            }
        }
    }

    let baseURL: URL
    let token: String
    private let session: URLSession
    private var filePrefix = "gradio_api/file="

    init(baseURL: String, token: String, session: URLSession? = nil) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))), url.scheme == "https", url.host?.hasSuffix(".hf.space") == true, url.user == nil, url.password == nil else {
            throw ClientError.badURL
        }
        self.baseURL = url
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 1800
        self.session = session ?? URLSession(configuration: config)
    }

    private func authorize(_ request: inout URLRequest) {
        if !token.isEmpty, request.url?.host == baseURL.host {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func upload(image: UIImage, fileName: String = "product.png") async throws -> GradioFileData {
        guard let data = image.pngData() else { throw ClientError.invalidResponse }
        let candidates = ["gradio_api/upload", "upload"]
        var lastError: Error?
        for route in candidates {
            do { return try await upload(data: data, fileName: fileName, route: route) }
            catch ClientError.http(404, _) { lastError = ClientError.http(404, route) }
            catch { throw error }
        }
        throw lastError ?? ClientError.invalidResponse
    }

    private func upload(data: Data, fileName: String, route: String) async throws -> GradioFileData {
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = baseURL.appending(path: route)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try validate(responseData, response)
        guard let raw = try JSONSerialization.jsonObject(with: responseData) as? [Any], let first = raw.first else {
            throw ClientError.invalidResponse
        }
        if let string = first as? String {
            return GradioFileData(path: string, url: nil, origName: fileName, meta: .init(type: "gradio.FileData"))
        }
        if let dict = first as? [String: Any] {
            let path = (dict["path"] as? String) ?? (dict["name"] as? String)
            guard let path else { throw ClientError.invalidResponse }
            return GradioFileData(path: path, url: dict["url"] as? String, origName: fileName, meta: .init(type: "gradio.FileData"))
        }
        throw ClientError.invalidResponse
    }

    // Classic Gradio event API: {"data":[...]}
    func call(endpoint: String, arguments: [GradioValue], timeout: TimeInterval = 900) async throws -> Any {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let routes = [
            (submit: "gradio_api/call/\(clean)", result: "gradio_api/call/\(clean)"),
            (submit: "call/\(clean)", result: "call/\(clean)")
        ]
        var errors: [String] = []
        for route in routes {
            do {
                return try await callRoute(submitRoute: route.submit, resultRoute: route.result, body: ["data": arguments.map(\.json)], timeout: timeout)
            } catch ClientError.http(404, let detail) { errors.append(detail) }
            catch { throw error }
        }
        throw ClientError.server(errors.joined(separator: " | "))
    }

    // Gradio 6 gr.api() endpoint: POST /gradio_api/call/v2/<name> with named JSON params.
    func callV2(endpoint: String, namedArguments: [String: GradioValue], timeout: TimeInterval = 900) async throws -> Any {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let body = namedArguments.mapValues(\.json)
        return try await callRoute(
            submitRoute: "gradio_api/call/v2/\(clean)",
            resultRoute: "gradio_api/call/\(clean)",
            body: body,
            timeout: timeout
        )
    }

    private func callRoute(submitRoute: String, resultRoute: String, body: [String: Any], timeout: TimeInterval) async throws -> Any {
        let submitURL = baseURL.appending(path: submitRoute)
        var submit = URLRequest(url: submitURL)
        submit.httpMethod = "POST"
        submit.timeoutInterval = 180
        authorize(&submit)
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.setValue("application/json", forHTTPHeaderField: "Accept")
        submit.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (submitData, submitResponse) = try await session.data(for: submit)
        try validate(submitData, submitResponse)
        guard let object = try JSONSerialization.jsonObject(with: submitData) as? [String: Any], let eventID = object["event_id"] as? String else {
            throw ClientError.noEventID
        }

        let resultURL = baseURL.appending(path: "\(resultRoute)/\(eventID)")
        var resultRequest = URLRequest(url: resultURL)
        resultRequest.httpMethod = "GET"
        resultRequest.timeoutInterval = timeout
        authorize(&resultRequest)
        resultRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (resultData, resultResponse) = try await session.data(for: resultRequest)
        do { try validate(resultData, resultResponse) }
        catch { throw ClientError.server("تم إرسال المهمة، لكن تعذر استلام النتيجة: \(error.localizedDescription)") }
        guard let output = try parseEventStream(resultData) else { throw ClientError.missingOutput }
        return output
    }


    /// Read the live schema before uploading or spending GPU quota.
    func callDiscovered(endpoint: String, values: [String: GradioValue], timeout: TimeInterval = 900) async throws -> Any {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var schema: [String: Any]?
        for route in ["gradio_api/info", "info"] {
            var request = URLRequest(url: baseURL.appending(path: route))
            authorize(&request)
            let (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 { continue }
            try validate(data, response)
            guard let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let endpoints = info["named_endpoints"] as? [String: Any],
                  let found = endpoints["/" + clean] as? [String: Any] ?? endpoints[clean] as? [String: Any] else {
                throw ClientError.server("الخدمة لا تعرض العملية \(clean). راجع رابط الخدمة في الإعدادات.")
            }
            filePrefix = route == "info" ? "file=" : "gradio_api/file="
            schema = found
            break
        }
        guard let schema, let parameters = schema["parameters"] as? [[String: Any]] else {
            throw ClientError.server("تعذر قراءة تعريف واجهة الخدمة. لم يتم بدء التوليد.")
        }
        var args: [Any] = []
        for parameter in parameters {
            guard let name = parameter["parameter_name"] as? String else { throw ClientError.invalidResponse }
            if let value = values[name] { args.append(value.json) }
            else if parameter["parameter_has_default"] as? Bool == true {
                args.append(parameter["parameter_default"] ?? NSNull())
            } else {
                throw ClientError.server("الخدمة تتطلب مدخلًا جديدًا: \(name). يلزم تحديث إعدادات العملية.")
            }
        }
        for prefix in ["gradio_api/call/", "call/"] {
            do {
                return try await callRoute(submitRoute: prefix + clean, resultRoute: prefix + clean, body: ["data": args], timeout: timeout)
            } catch ClientError.http(404, _) { continue }
        }
        throw ClientError.http(404, clean)
    }

    func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        authorize(&request)
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ClientError.invalidResponse }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "ObjectStudio-\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    func outputURL(in object: Any, preferredExtensions: Set<String>) -> URL? {
        if let remote = Self.firstURL(in: object, preferredExtensions: preferredExtensions) { return remote }
        if let dict = object as? [String: Any] {
            if let path = dict["path"] as? String, preferredExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
                return baseURL.appending(path: filePrefix + path)
            }
            for value in dict.values {
                if let url = outputURL(in: value, preferredExtensions: preferredExtensions) { return url }
            }
        }
        if let values = object as? [Any] {
            for value in values {
                if let url = outputURL(in: value, preferredExtensions: preferredExtensions) { return url }
            }
        }
        return nil
    }

    static func firstURL(in object: Any, preferredExtensions: Set<String> = []) -> URL? {
        if let string = object as? String, let url = URL(string: string), ["https"].contains(url.scheme ?? "") {
            if preferredExtensions.isEmpty || preferredExtensions.contains(url.pathExtension.lowercased()) { return url }
        }
        if let dict = object as? [String: Any] {
            for key in ["url", "value", "path", "video", "name"] {
                if let item = dict[key], let url = firstURL(in: item, preferredExtensions: preferredExtensions) { return url }
            }
            for value in dict.values {
                if let url = firstURL(in: value, preferredExtensions: preferredExtensions) { return url }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let url = firstURL(in: value, preferredExtensions: preferredExtensions) { return url }
            }
        }
        return nil
    }

    private func parseEventStream(_ data: Data) throws -> Any? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var currentEvent = ""
        var completed: Any?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if currentEvent == "error" { throw ClientError.server(payload) }
            if currentEvent == "complete" {
                guard let jsonData = payload.data(using: .utf8) else { throw ClientError.invalidResponse }
                completed = try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed)
            }
        }
        return completed
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClientError.http(http.statusCode, String(text.prefix(300)))
        }
    }
}
