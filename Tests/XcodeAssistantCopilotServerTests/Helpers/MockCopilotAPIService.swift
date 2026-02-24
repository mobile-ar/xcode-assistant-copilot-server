@testable import XcodeAssistantCopilotServer
import Foundation

final class MockCopilotAPIService: CopilotAPIServiceProtocol, @unchecked Sendable {
    var models: [CopilotModel] = []
    var streamChatCompletionsResults: [Result<AsyncThrowingStream<SSEEvent, Error>, Error>] = []
    var streamResponsesResults: [Result<AsyncThrowingStream<SSEEvent, Error>, Error>] = []
    private(set) var streamChatCompletionsCallCount = 0
    private(set) var streamResponsesCallCount = 0
    private(set) var capturedChatRequests: [CopilotChatRequest] = []

    func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        models
    }

    func streamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let index = streamChatCompletionsCallCount
        streamChatCompletionsCallCount += 1
        capturedChatRequests.append(request)
        guard index < streamChatCompletionsResults.count else {
            return AsyncThrowingStream { $0.finish() }
        }
        return try streamChatCompletionsResults[index].get()
    }

    func streamResponses(
        request: ResponsesAPIRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let index = streamResponsesCallCount
        streamResponsesCallCount += 1
        guard index < streamResponsesResults.count else {
            return AsyncThrowingStream { $0.finish() }
        }
        return try streamResponsesResults[index].get()
    }
}

extension MockCopilotAPIService {
    static func makeToolCallStream(toolCalls: [ToolCall], content: String = "") -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let encoder = JSONEncoder()

            let indexedToolCalls = toolCalls.enumerated().map { index, tc in
                ToolCall(
                    index: index,
                    id: tc.id,
                    type: tc.type,
                    function: tc.function
                )
            }

            let delta = ChunkDelta(
                role: .assistant,
                content: content.isEmpty ? nil : content,
                toolCalls: indexedToolCalls
            )
            let chunk = ChatCompletionChunk(
                id: "test-completion",
                model: "test-model",
                choices: [ChunkChoice(delta: delta)]
            )
            if let data = try? encoder.encode(chunk),
               let json = String(data: data, encoding: .utf8) {
                continuation.yield(SSEEvent(data: json))
            }

            let finishChunk = ChatCompletionChunk(
                id: "test-completion",
                model: "test-model",
                choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "tool_calls")]
            )
            if let data = try? encoder.encode(finishChunk),
               let json = String(data: data, encoding: .utf8) {
                continuation.yield(SSEEvent(data: json))
            }

            continuation.yield(SSEEvent(data: "[DONE]"))
            continuation.finish()
        }
    }

    static func makeContentStream(content: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let encoder = JSONEncoder()

            let delta = ChunkDelta(role: .assistant, content: content)
            let chunk = ChatCompletionChunk(
                id: "test-completion",
                model: "test-model",
                choices: [ChunkChoice(delta: delta)]
            )
            if let data = try? encoder.encode(chunk),
               let json = String(data: data, encoding: .utf8) {
                continuation.yield(SSEEvent(data: json))
            }

            let stopChunk = ChatCompletionChunk(
                id: "test-completion",
                model: "test-model",
                choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "stop")]
            )
            if let data = try? encoder.encode(stopChunk),
               let json = String(data: data, encoding: .utf8) {
                continuation.yield(SSEEvent(data: json))
            }

            continuation.yield(SSEEvent(data: "[DONE]"))
            continuation.finish()
        }
    }
}