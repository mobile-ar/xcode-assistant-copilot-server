@testable import XcodeAssistantCopilotServer
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import Testing

@Suite("ChatCompletionsHandler")
struct ChatCompletionsHandlerTests {

    @Test("Returns 400 for invalid JSON body")
    func handleReturns400ForInvalidJSON() async throws {
        let handler = makeHandler()
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: ByteBuffer(string: "{ not valid json }")
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("Returns 400 when model is empty")
    func handleReturns400ForEmptyModel() async throws {
        let handler = makeHandler()
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody(model: "")
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("Returns 400 when messages array is empty")
    func handleReturns400ForEmptyMessages() async throws {
        let handler = makeHandler()
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeEmptyMessagesBody()
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("Returns 401 when authentication fails")
    func handleReturns401WhenAuthFails() async throws {
        let authService = MockAuthService()
        authService.shouldThrow = AuthServiceError.notAuthenticated
        let handler = makeHandler(authService: authService)
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test("Uses direct strategy when no MCP bridge is present")
    func handleUsesDirectStrategyWhenNoBridge() async throws {
        let directStrategy = MockChatCompletion()
        let agentStrategy = MockChatCompletion()
        let handler = makeHandler(
            bridgeHolder: MCPBridgeHolder(),
            directStrategy: directStrategy,
            agentStrategy: agentStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .ok)
        }

        #expect(directStrategy.streamCallCount == 1)
        #expect(agentStrategy.streamCallCount == 0)
    }

    @Test("Uses agent strategy when MCP bridge is present")
    func handleUsesAgentStrategyWhenBridgePresent() async throws {
        let directStrategy = MockChatCompletion()
        let agentStrategy = MockChatCompletion()
        let handler = makeHandler(
            bridgeHolder: MCPBridgeHolder(MockMCPBridgeService()),
            directStrategy: directStrategy,
            agentStrategy: agentStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .ok)
        }

        #expect(agentStrategy.streamCallCount == 1)
        #expect(directStrategy.streamCallCount == 0)
    }

    @Test("Passes correct request and credentials to strategy")
    func handlePassesCorrectRequestToStrategy() async throws {
        let authService = MockAuthService()
        authService.credentials = CopilotCredentials(
            token: "test-token-123",
            apiEndpoint: "https://test.api.github.com"
        )
        let directStrategy = MockChatCompletion()
        let handler = makeHandler(
            authService: authService,
            bridgeHolder: MCPBridgeHolder(),
            directStrategy: directStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody(model: "claude-sonnet-4")
            )
            #expect(response.status == .ok)
        }

        let receivedRequest = try #require(directStrategy.lastRequest)
        #expect(receivedRequest.model == "claude-sonnet-4")
        #expect(receivedRequest.messages.count == 1)

        let receivedCredentials = try #require(directStrategy.lastCredentials)
        #expect(receivedCredentials.token == "test-token-123")
        #expect(receivedCredentials.apiEndpoint == "https://test.api.github.com")
    }

    @Test("Retries with fresh credentials when strategy throws unauthorized")
    func handleRetriesOnUnauthorized() async throws {
        let authService = MockAuthService()
        authService.credentialsSequence = [
            CopilotCredentials(token: "stale-token", apiEndpoint: "https://api.github.com"),
            CopilotCredentials(token: "fresh-token", apiEndpoint: "https://api.github.com")
        ]
        let directStrategy = MockChatCompletion()
        directStrategy.responseSequence = [
            .failure(CopilotAPIError.unauthorized),
            .success(Response(
                status: .ok,
                headers: [:],
                body: .init(asyncSequence: AsyncStream<ByteBuffer> { $0.finish() })
            ))
        ]
        let handler = makeHandler(
            authService: authService,
            bridgeHolder: MCPBridgeHolder(),
            directStrategy: directStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .ok)
        }

        #expect(directStrategy.streamCallCount == 2)
        #expect(authService.invalidateCallCount == 1)
    }

    @Test("Returns error when retry also fails with unauthorized")
    func handleFailsWhenRetryAlsoUnauthorized() async throws {
        let authService = MockAuthService()
        authService.credentialsSequence = [
            CopilotCredentials(token: "stale-token", apiEndpoint: "https://api.github.com"),
            CopilotCredentials(token: "also-stale-token", apiEndpoint: "https://api.github.com")
        ]
        let directStrategy = MockChatCompletion()
        directStrategy.errorToThrow = CopilotAPIError.unauthorized
        let handler = makeHandler(
            authService: authService,
            bridgeHolder: MCPBridgeHolder(),
            directStrategy: directStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .internalServerError)
        }
    }

    @Test("Does not retry on non-unauthorized errors")
    func handleDoesNotRetryOnOtherErrors() async throws {
        let authService = MockAuthService()
        let directStrategy = MockChatCompletion()
        directStrategy.errorToThrow = CopilotAPIError.streamingFailed("connection lost")
        let handler = makeHandler(
            authService: authService,
            bridgeHolder: MCPBridgeHolder(),
            directStrategy: directStrategy
        )
        let app = makeTestApp(handler: handler)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/test",
                method: .post,
                body: try makeCompletionBody()
            )
            #expect(response.status == .internalServerError)
        }

        #expect(directStrategy.streamCallCount == 1)
        #expect(authService.invalidateCallCount == 0)
    }
}

private func makeHandler(
    authService: MockAuthService = MockAuthService(),
    configurationStore: ConfigurationStore = ConfigurationStore(initial: ServerConfiguration()),
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    directStrategy: MockChatCompletion = MockChatCompletion(),
    agentStrategy: MockChatCompletion = MockChatCompletion(),
    logger: LoggerProtocol = MockLogger()
) -> ChatCompletionsHandler {
    ChatCompletionsHandler(
        authService: authService,
        configurationStore: configurationStore,
        bridgeHolder: bridgeHolder,
        directStrategy: directStrategy,
        agentStrategy: agentStrategy,
        logger: logger
    )
}

private func makeTestApp(handler: ChatCompletionsHandler) -> some ApplicationProtocol {
    let router = Router()
    router.post("test") { request, _ in
        try await handler.handle(request: request)
    }
    return Application(router: router)
}

private func makeCompletionBody(model: String = "gpt-4o") throws -> ByteBuffer {
    let request = ChatCompletionRequest(
        model: model,
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
    let data = try JSONEncoder().encode(request)
    return ByteBuffer(bytes: data)
}

private func makeEmptyMessagesBody() throws -> ByteBuffer {
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: []
    )
    let data = try JSONEncoder().encode(request)
    return ByteBuffer(bytes: data)
}
