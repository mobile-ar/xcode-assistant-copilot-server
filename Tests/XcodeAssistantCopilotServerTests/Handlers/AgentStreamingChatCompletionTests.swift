@testable import XcodeAssistantCopilotServer
import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import Synchronization
import Testing

@Suite("AgentStreamingChatCompletion Tests")
struct AgentStreamingChatCompletionTests {

    @Test func streamResponseReturns200() async throws {
        let bridge = MockMCPBridgeService()
        let holder = MCPBridgeHolder(bridge)
        let strategy = makeStrategy(bridgeHolder: holder)
        let request = makeRequest()

        let response = await strategy.streamResponse(
            request: request,
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.status == .ok)

        try await drainResponseBody(response)
    }

    @Test func streamResponseReturnsSSEContentType() async throws {
        let bridge = MockMCPBridgeService()
        let holder = MCPBridgeHolder(bridge)
        let strategy = makeStrategy(bridgeHolder: holder)
        let request = makeRequest()

        let response = await strategy.streamResponse(
            request: request,
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.headers[.contentType] == "text/event-stream")

        try await drainResponseBody(response)
    }

    @Test func streamResponseDelegatesToAgentLoopService() async throws {
        let bridge = MockMCPBridgeService()
        let holder = MCPBridgeHolder(bridge)
        let mockAgentLoopService = MockAgentLoopService()
        let strategy = makeStrategy(bridgeHolder: holder, agentLoopService: mockAgentLoopService)
        let request = makeRequest(model: "gpt-4o")

        let response = await strategy.streamResponse(
            request: request,
            credentials: testCredentials,
            configuration: testConfiguration
        )

        try await drainResponseBody(response)

        #expect(mockAgentLoopService.runCallCount == 1)
        #expect(mockAgentLoopService.lastRequest?.model == "gpt-4o")
    }

    @Test func streamResponseWorksWithoutBridge() async throws {
        let holder = MCPBridgeHolder()
        let strategy = makeStrategy(bridgeHolder: holder)
        let request = makeRequest()

        let response = await strategy.streamResponse(
            request: request,
            credentials: testCredentials,
            configuration: testConfiguration
        )

        #expect(response.status == .ok)

        try await drainResponseBody(response)
    }
}

private func makeStrategy(
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    agentLoopService: AgentLoopServiceProtocol = MockAgentLoopService(),
    logger: LoggerProtocol = MockLogger()
) -> AgentStreamingChatCompletion {
    AgentStreamingChatCompletion(
        bridgeHolder: bridgeHolder,
        agentLoopService: agentLoopService,
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

private final class CollectedBuffers: Sendable {
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

private struct CollectingBodyWriter: ResponseBodyWriter {
    let storage: CollectedBuffers

    mutating func write(_ buffer: ByteBuffer) async throws {
        storage.append(buffer)
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

@discardableResult
private func drainResponseBody(_ response: Response) async throws -> Data {
    let storage = CollectedBuffers()
    let writer = CollectingBodyWriter(storage: storage)
    try await response.body.write(writer)
    return storage.collectedData
}
