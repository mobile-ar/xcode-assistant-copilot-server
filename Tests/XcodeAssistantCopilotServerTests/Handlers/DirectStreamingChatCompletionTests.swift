@testable import XcodeAssistantCopilotServer
import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import Synchronization
import Testing

@Suite("DirectStreamingChatCompletion")
struct DirectStreamingChatCompletionTests {

    @Test func streamResponseReturns200WithValidRequest() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hello world"))
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        let response = try await strategy.streamResponse(
            request: makeRequest(),
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.status == .ok)
    }

    @Test func streamResponseReturnsSSEContentType() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Hi"))
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        let response = try await strategy.streamResponse(
            request: makeRequest(),
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.headers[.contentType] == "text/event-stream")
    }

    @Test func streamResponseReturnsErrorWhenStreamingFails() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 500, body: "upstream failure"))
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        let response = try await strategy.streamResponse(
            request: makeRequest(),
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.status == .internalServerError)
    }

    @Test func streamResponseBodyContainsDone() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Done test"))
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        let response = try await strategy.streamResponse(
            request: makeRequest(),
            credentials: testCredentials,
            configuration: testConfiguration
        )

        let bodyString = try await drainResponseBodyString(response)
        #expect(bodyString.contains("data: [DONE]"))
    }

    @Test func streamResponseForwardsEventsFromUpstream() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "forwarded"))
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        let response = try await strategy.streamResponse(
            request: makeRequest(),
            credentials: testCredentials,
            configuration: testConfiguration
        )

        let bodyString = try await drainResponseBodyString(response)

        let dataLines = bodyString
            .components(separatedBy: "\n")
            .filter { line in line.hasPrefix("data: ") && !line.hasPrefix("data: [DONE]") }
            .map { line in String(line.dropFirst("data: ".count)) }

        #expect(!dataLines.isEmpty)
        for payload in dataLines {
            let data = try #require(payload.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            #expect(json is [String: Any])
        }
    }

    @Test func streamResponseThrowsUnauthorized() async throws {
        let mockAPI = MockCopilotAPIService()
        mockAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.unauthorized)
        ]
        let strategy = makeStrategy(copilotAPI: mockAPI)

        do {
            _ = try await strategy.streamResponse(
                request: makeRequest(),
                credentials: testCredentials,
                configuration: testConfiguration
            )
            Issue.record("Expected CopilotAPIError.unauthorized to be thrown")
        } catch let error as CopilotAPIError {
            guard case .unauthorized = error else {
                Issue.record("Expected .unauthorized but got \(error)")
                return
            }
        }
    }

    private func makeStrategy(
        copilotAPI: CopilotAPIServiceProtocol = MockCopilotAPIService(),
        modelEndpointResolver: ModelEndpointResolverProtocol = MockModelEndpointResolver(),
        reasoningEffortResolver: ReasoningEffortResolverProtocol = MockReasoningEffortResolver(),
        logger: LoggerProtocol = MockLogger()
    ) -> DirectStreamingChatCompletion {
        DirectStreamingChatCompletion(
            copilotAPI: copilotAPI,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            responsesTranslator: ResponsesAPITranslator(logger: logger),
            logger: logger
        )
    }

    private func makeRequest(model: String = "gpt-4o") -> ChatCompletionRequest {
        ChatCompletionRequest(
            model: model,
            messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
        )
    }

    private let testCredentials = CopilotCredentials(token: "test-token", apiEndpoint: "https://api.github.com")
    private let testConfiguration = ServerConfiguration()
}

private final class CollectedStreamBuffers: Sendable {
    private struct State {
        var buffers: [ByteBuffer] = []
    }

    private let mutex = Mutex(State())

    var collectedData: Data {
        mutex.withLock { state in
            var combined = ByteBuffer()
            for buf in state.buffers {
                var copy = buf
                combined.writeBuffer(&copy)
            }
            return Data(buffer: combined)
        }
    }

    func append(_ buffer: ByteBuffer) {
        mutex.withLock { $0.buffers.append(buffer) }
    }
}

private struct CollectingStreamBodyWriter: ResponseBodyWriter {
    let storage: CollectedStreamBuffers

    mutating func write(_ buffer: ByteBuffer) async throws {
        storage.append(buffer)
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

private func drainResponseBodyString(_ response: Response) async throws -> String {
    let storage = CollectedStreamBuffers()
    let writer = CollectingStreamBodyWriter(storage: storage)
    try await response.body.write(writer)
    return String(data: storage.collectedData, encoding: .utf8) ?? ""
}
