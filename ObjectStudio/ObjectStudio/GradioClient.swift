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
        case badURL, invalidResponse, server(String), noEventID, timedOut, missingOutput

        var errorDescription: String? {
            switch self {
            case .badURL: return "رابط Hugging Face غير صحيح."
            case .invalidResponse: return "استجابة Hugging Face غير مفهومة."
            case .server(let text): return text
            case .noEventID: return "لم يرجع السيرفر رقم العملية."
            case .timedOut: return "انتهى وقت الانتظار قبل اكتمال العملية."
            case .missingOutput: return "اكتملت العملية بدون ملف نتيجة."
            }
        }
    }

    let baseURL: URL
    let token: String
    private let session: URLSession

    init(baseURL: String, token: String) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw ClientError.badURL
        }
        self.baseURL = url
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 1800
        self.session = URLSession(configuration: config)
    }

    private func authorize(_ request: inout URLRequest) {
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func upload(image: UIImage, fileName: String = "product.png") async throws -> GradioFileData {
        guard let data = image.pngData() else { throw ClientError.invalidResponse }
        let candidates = ["gradio_api/upload", "upload"]
        var lastError: Error?

        for route in candidates {
            do {
                return try await upload(data: data, fileName: fileName, route: route)
            } catch {
                lastError = error
            }
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

    /// Works with both older Spaces (Gradio 4.x: /call/...) and newer Spaces
    /// (/gradio_api/call/...). Each route uses {"data": [...]} and returns an event_id.
    func call(endpoint: String, arguments: [GradioValue], timeout: TimeInterval = 900) async throws -> Any {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let routes = [
            (submit: "gradio_api/call/\(clean)", result: "gradio_api/call/\(clean)"),
            (submit: "call/\(clean)", result: "call/\(clean)")
        ]

        var errors: [String] = []
        for route in routes {
            do {
                return try await callRoute(submitRoute: route.submit, resultRoute: route.result, arguments: arguments, timeout: timeout)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let compact = errors.joined(separator: " | ")
        throw ClientError.server(compact.isEmpty ? "تعذر تشغيل Hugging Face Space." : compact)
    }

    private func callRoute(submitRoute: String, resultRoute: String, arguments: [GradioValue], timeout: TimeInterval) async throws -> Any {
        let submitURL = baseURL.appending(path: submitRoute)
        var submit = URLRequest(url: submitURL)
        submit.httpMethod = "POST"
        submit.timeoutInterval = 180
        authorize(&submit)
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.setValue("application/json", forHTTPHeaderField: "Accept")
        submit.httpBody = try JSONSerialization.data(withJSONObject: ["data": arguments.map(\.json)])

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
        try validate(resultData, resultResponse)
        guard let output = try parseEventStream(resultData) else { throw ClientError.missingOutput }
        return output
    }

    func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        authorize(&request)
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ClientError.invalidResponse
        }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory.appending(path: "ObjectStudio-\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    static func firstURL(in object: Any, preferredExtensions: Set<String> = []) -> URL? {
        if let string = object as? String, let url = URL(string: string), url.scheme != nil {
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
                completed = try JSONSerialization.jsonObject(with: jsonData)
            }
        }
        return completed
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClientError.server("HTTP \(http.statusCode): \(text.prefix(350))")
        }
    }
}
