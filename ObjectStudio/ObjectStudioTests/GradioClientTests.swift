import XCTest
@testable import ObjectStudio

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, text) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class GradioClientTests: XCTestCase {
    func makeClient() throws -> GradioClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return try GradioClient(baseURL: "https://example.hf.space", token: "", session: URLSession(configuration: configuration))
    }

    func testServerFailureDoesNotSubmitAnotherGPUJob() async throws {
        var submissions = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "POST" {
                submissions += 1
                return (200, #"{"event_id":"job"}"#)
            }
            return (200, "event: error\ndata: null\n\n")
        }
        do {
            _ = try await makeClient().call(endpoint: "generate", arguments: [])
            XCTFail("Expected GPU failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("GPU")) }
        XCTAssertEqual(submissions, 1)
    }

    func testMissingResultDoesNotResubmit() async throws {
        var submissions = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "POST" { submissions += 1; return (200, #"{"event_id":"job"}"#) }
            return (404, #"{"detail":"Not Found"}"#)
        }
        do { _ = try await makeClient().call(endpoint: "generate", arguments: []); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("تم إرسال المهمة")) }
        XCTAssertEqual(submissions, 1)
    }

    func testLegacySchemaAndRelativeFileOutput() async throws {
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/gradio_api/info", "/gradio_api/call/generate": return (404, "{}")
            case "/info":
                return (200, #"{"named_endpoints":{"/generate":{"parameters":[{"parameter_name":"seed","parameter_has_default":true,"parameter_default":42}]}}}"#)
            case "/call/generate": return (200, #"{"event_id":"job"}"#)
            default: return (200, "event: heartbeat\ndata: null\n\nevent: complete\ndata: [{\"path\":\"/tmp/model.glb\"}]\n\n")
            }
        }
        let client = try makeClient()
        let result = try await client.callDiscovered(endpoint: "generate", values: [:])
        let url = await client.outputURL(in: result, preferredExtensions: ["glb"])
        XCTAssertEqual(url?.absoluteString, "https://example.hf.space/file=/tmp/model.glb")
    }

    func testRejectsInsecureOrUnrelatedTokenDestinations() throws {
        for host in ["http://example.hf.space", "https://hf.space.attacker.test", "file:///tmp/test"] {
            XCTAssertThrowsError(try GradioClient(baseURL: host, token: "test"))
        }
    }
}
