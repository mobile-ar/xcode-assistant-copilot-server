@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@Suite("ChatCompletions endpoint integration")
struct ChatCompletionsIntegrationTests {

    private static let xcodeHeaders: HTTPFields = [
        .userAgent: "Xcode/26.0",
        .contentType: "application/json"
    ]

    @Test("POST /v1/chat/completions returns 200 with a valid streaming request")
    func completionsReturns200() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello"))
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            #expect(response.status == .ok)
        }
    }

    @Test("POST /v1/chat/completions response has text/event-stream content-type")
    func completionsResponseHasSSEContentType() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello"))
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            #expect(response.headers[.contentType] == "text/event-stream")
        }
    }

    @Test("POST /v1/chat/completions SSE body terminates with [DONE]")
    func completionsBodyTerminatesWithDone() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello"))
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            let body = String(buffer: response.body)
            #expect(body.contains("data: [DONE]"))
        }
    }

    @Test("POST /v1/chat/completions SSE body contains data lines with valid JSON chunks")
    func completionsBodyContainsValidSSEDataLines() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello"))
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            let dataLines = sseDataLines(from: String(buffer: response.body))
            #expect(!dataLines.isEmpty)
            for payload in dataLines {
                let data = try #require(payload.data(using: .utf8))
                _ = try JSONSerialization.jsonObject(with: data)
            }
        }
    }

    @Test("POST /v1/chat/completions returns 401 when authentication fails")
    func completionsReturns401WhenAuthFails() async throws {
        let authService = MockAuthService()
        authService.shouldThrow = AuthServiceError.notAuthenticated
        let harness = ServerTestHarness(authService: authService)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test("POST /v1/chat/completions returns 400 for a malformed request body")
    func completionsReturns400ForMalformedBody() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: ByteBuffer(string: "{ not valid json }")
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("POST /v1/chat/completions returns 403 when the Xcode User-Agent header is absent")
    func completionsReturns403WithoutXcodeUserAgent() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: [.contentType: "application/json"],
                body: try makeCompletionRequestBody()
            )
            #expect(response.status == .forbidden)
        }
    }

    @Test("POST /v1/chat/completions response includes CORS allow-origin header")
    func completionsResponseIncludesCORSHeader() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello"))
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: Self.xcodeHeaders,
                body: try makeCompletionRequestBody()
            )
            #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
        }
    }
}

private func makeCompletionRequestBody(model: String = "gpt-4o") throws -> ByteBuffer {
    let request = ChatCompletionRequest(
        model: model,
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
    let data = try JSONEncoder().encode(request)
    return ByteBuffer(bytes: data)
}

private func sseDataLines(from body: String) -> [String] {
    body
        .components(separatedBy: "\n")
        .filter { $0.hasPrefix("data: ") && !$0.hasPrefix("data: [DONE]") }
        .map { String($0.dropFirst("data: ".count)) }
        .filter { !$0.isEmpty }
}