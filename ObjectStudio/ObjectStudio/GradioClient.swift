import Foundation
import UIKit

struct GradioFileData: Codable {
    let path: String
    let url: String?
    let origName: String
    let meta: Meta

    struct Meta: Codable { let type: String
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
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { throw ClientError.badURL }
        self.baseURL = url
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 1800
        self.session = URLSession(configuration: config)
    }

    private func authorize(_ request: inout URLRequest) {
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    func upload(image: UIImage, fileName: String = "product.png") async throws -> GradioFileData {
        guard let data = image.pngData() else { throw ClientError.invalidResponse }
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = baseURL.appending(path: "gradio_api/upload")
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
        guard let raw = try JSONSerialization.jsonObject(with: responseData) as? [Any],
              let first = raw.first else { throw ClientError.invalidResponse }
        let path: String
        if let string = first as? String { path = string }
        else if let dict = first as? [String: Any], let string = dict["path"] as? String { path = string }
        else { throw ClientError.invalidResponse }
        return GradioFileData(path: path, url: nil, origName: fileName, meta: .init(type: "gradio.FileData"))
    }

    func call(endpoint: String, parameters: [String: GradioValue], pollEvery: UInt64 = 2_000_000_000, timeout: TimeInterval = 900) async throws -> Any {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appending(path: "gradio_api/call/v2/\(clean)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters.mapValues(\.json))
        let (data, response) = try await session.data(for: request)
        try validate(data, response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventID = object["event_id"] as? String else { throw ClientError.noEventID }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pollURL = baseURL.appending(path: "gradio_api/call/\(clean)/\(eventID)")
            var poll = URLRequest(url: pollURL)
            authorize(&poll)
            let (pollData, pollResponse) = try await session.data(for: poll)
            try validate(pollData, pollResponse)
            if let value = try parseEventStream(pollData) { return value }
            try await Task.sleep(nanoseconds: pollEvery)
        }
        throw ClientError.timedOut
    }

    func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        authorize(&request)
        let (temp, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ClientError.invalidResponse }
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
            for key in ["url", "value", "path", "video"] {
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
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") { currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if currentEvent == "error" { throw ClientError.server(payload) }
                if currentEvent == "complete" {
                    guard let jsonData = payload.data(using: .utf8) else { throw ClientError.invalidResponse }
                    return try JSONSerialization.jsonObject(with: jsonData)
                }
            }
        }
        return nil
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClientError.server("Hugging Face: \(text.prefix(400))")
        }
    }
}
