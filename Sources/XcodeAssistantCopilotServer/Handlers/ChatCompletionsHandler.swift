import Foundation
import Hummingbird
import NIOCore

struct ChatCompletionsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let configurationStore: ConfigurationStore
    private let bridgeHolder: MCPBridgeHolder
    private let directStrategy: ChatCompletionProtocol
    private let agentStrategy: ChatCompletionProtocol
    private let logger: LoggerProtocol

    init(
        authService: AuthServiceProtocol,
        configurationStore: ConfigurationStore,
        bridgeHolder: MCPBridgeHolder,
        directStrategy: ChatCompletionProtocol,
        agentStrategy: ChatCompletionProtocol,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.configurationStore = configurationStore
        self.bridgeHolder = bridgeHolder
        self.directStrategy = directStrategy
        self.agentStrategy = agentStrategy
        self.logger = logger
    }

    func handle(request: Request) async throws -> Response {
        let configuration = await configurationStore.current()
        do {
            return try await request.body.consumeWithCancellationOnInboundClose { body in
                let bodyBuffer = try await body.collect(upTo: configuration.bodyLimitBytes)

                let completionRequest: ChatCompletionRequest
                do {
                    completionRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: bodyBuffer)
                } catch {
                    self.logger.warn("Invalid request body: \(error)")
                    return ErrorResponseBuilder.build(status: .badRequest, type: "invalid_request_error", message: "Invalid request body: \(error)")
                }

                guard !completionRequest.model.isEmpty else {
                    return ErrorResponseBuilder.build(status: .badRequest, type: "invalid_request_error", message: "Model is required")
                }

                guard !completionRequest.messages.isEmpty else {
                    return ErrorResponseBuilder.build(status: .badRequest, type: "invalid_request_error", message: "Messages are required")
                }

                let credentials: CopilotCredentials
                do {
                    credentials = try await self.authService.getValidCopilotToken()
                } catch {
                    self.logger.error("Authentication failed: \(error)")
                    return ErrorResponseBuilder.build(status: .unauthorized, type: "api_error", message: "Authentication failed: \(error)")
                }

                return try await self.streamWithRetry(completionRequest: completionRequest, credentials: credentials, configuration: configuration)
            }
        } catch is CancellationError {
            logger.info("Request cancelled — user stopped the request from Xcode.")
            throw CancellationError()
        }
    }

    private func streamWithRetry(completionRequest: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async throws -> Response {
        let strategy = await resolveStrategy()
        return try await authService.retryingOnUnauthorized(credentials: credentials) { retryCredentials in
            try await strategy.streamResponse(request: completionRequest, credentials: retryCredentials, configuration: configuration)
        }
    }

    private func resolveStrategy() async -> ChatCompletionProtocol {
        if await bridgeHolder.bridge != nil {
            logger.info("Using agent streaming strategy")
            return agentStrategy
        } else {
            logger.info("Using direct streaming strategy")
            return directStrategy
        }
    }
}