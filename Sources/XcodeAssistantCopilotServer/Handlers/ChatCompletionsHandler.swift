import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct ChatCompletionsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let bridgeHolder: MCPBridgeHolder
    private let modelEndpointResolver: ModelEndpointResolverProtocol
    private let reasoningEffortResolver: ReasoningEffortResolverProtocol
    private let responsesTranslator: ResponsesAPITranslator
    private let configurationStore: ConfigurationStore
    private let logger: LoggerProtocol
    private let eventNormalizer: SSEEventNormalizerProtocol
    private let agentLoopService: AgentLoopServiceProtocol

    public init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        bridgeHolder: MCPBridgeHolder,
        modelEndpointResolver: ModelEndpointResolverProtocol,
        reasoningEffortResolver: ReasoningEffortResolverProtocol,
        configurationStore: ConfigurationStore,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.bridgeHolder = bridgeHolder
        self.modelEndpointResolver = modelEndpointResolver
        self.reasoningEffortResolver = reasoningEffortResolver
        self.responsesTranslator = ResponsesAPITranslator(logger: logger)
        self.configurationStore = configurationStore
        self.logger = logger

        let mcpToolExecutor = MCPToolExecutor(
            bridgeHolder: bridgeHolder,
            configurationStore: configurationStore,
            logger: logger
        )
        self.eventNormalizer = SSEEventNormalizer()
        self.agentLoopService = AgentLoopService(
            copilotAPI: copilotAPI,
            mcpToolExecutor: mcpToolExecutor,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            responsesTranslator: ResponsesAPITranslator(logger: logger),
            configurationStore: configurationStore,
            logger: logger
        )
    }

    init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        bridgeHolder: MCPBridgeHolder,
        modelEndpointResolver: ModelEndpointResolverProtocol,
        reasoningEffortResolver: ReasoningEffortResolverProtocol,
        configurationStore: ConfigurationStore,
        logger: LoggerProtocol,
        eventNormalizer: SSEEventNormalizerProtocol,
        agentLoopService: AgentLoopServiceProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.bridgeHolder = bridgeHolder
        self.modelEndpointResolver = modelEndpointResolver
        self.reasoningEffortResolver = reasoningEffortResolver
        self.responsesTranslator = ResponsesAPITranslator(logger: logger)
        self.configurationStore = configurationStore
        self.logger = logger
        self.eventNormalizer = eventNormalizer
        self.agentLoopService = agentLoopService
    }

    public func handle(request: Request) async throws -> Response {
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

            if await self.bridgeHolder.bridge != nil {
                return await self.handleAgentStreaming(request: completionRequest, credentials: credentials, configuration: configuration)
            } else {
                return await self.handleDirectStreaming(request: completionRequest, credentials: credentials, configuration: configuration)
            }
        }
        } catch is CancellationError {
            logger.info("Request cancelled — user stopped the request from Xcode.")
            throw CancellationError()
        }
    }

    private func handleDirectStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async -> Response {
        let copilotRequest = buildCopilotRequest(from: request, configuration: configuration)

        let eventStream: AsyncThrowingStream<SSEEvent, Error>
        do {
            eventStream = try await streamForModel(copilotRequest: copilotRequest, credentials: credentials)
            logger.debug("Stream obtained successfully for model: \(copilotRequest.model)")
        } catch {
            logger.error("Copilot API streaming failed: \(error)")
            return ErrorResponseBuilder.build(status: .internalServerError, type: "api_error", message: "Failed to start streaming: \(error)")
        }

        logger.info("Streaming response (direct mode)")

        let responseStream = AsyncStream<ByteBuffer> { continuation in
            let task = Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { [configuration] in
                            try await Task.sleep(for: .seconds(configuration.timeouts.requestTimeoutSeconds))
                            throw ChatCompletionsHandlerError.timeout
                        }

                        group.addTask { [logger, eventNormalizer] in
                            var forwardedEventCount = 0
                            do {
                                for try await event in eventStream {
                                    if Task.isCancelled {
                                        logger.debug("Direct stream: cancelled after \(forwardedEventCount) forwarded events")
                                        break
                                    }

                                    if event.isDone {
                                        logger.debug("Direct stream: received [DONE] after \(forwardedEventCount) forwarded events")
                                        let doneBuffer = ByteBuffer(string: "data: [DONE]\n\n")
                                        continuation.yield(doneBuffer)
                                        break
                                    }

                                    forwardedEventCount += 1
                                    if forwardedEventCount <= 3 || forwardedEventCount % 50 == 0 {
                                        logger.debug("Direct stream: forwarding event #\(forwardedEventCount), data length=\(event.data.count), preview=\(event.data.prefix(1500))")
                                    }
                                    let sseData = "data: \(eventNormalizer.normalizeEventData(event.data))\n\n"
                                    let buffer = ByteBuffer(string: sseData)
                                    continuation.yield(buffer)
                                }
                            } catch {
                                logger.error("Direct stream error after \(forwardedEventCount) events: \(error)")
                            }
                            logger.debug("Direct stream: finished with \(forwardedEventCount) total forwarded events")
                            continuation.finish()
                        }

                        try await group.next()
                        group.cancelAll()
                    }
                } catch {
                    if error is ChatCompletionsHandlerError {
                        logger.warn("Stream timed out after \(configuration.timeouts.requestTimeoutSeconds) seconds")
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return Response(status: .ok, headers: sseHeaders(), body: .init(asyncSequence: responseStream))
    }

    private func handleAgentStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async -> Response {
        let completionId = ChatCompletionChunk.makeCompletionId()
        let model = request.model

        var mcpToolServerMap: [String: String] = [:]
        var allTools = request.tools ?? []

        if let mcpBridge = await bridgeHolder.bridge {
            do {
                let mcpTools = try await mcpBridge.listTools()
                for tool in mcpTools {
                    mcpToolServerMap[tool.name] = tool.serverName
                    allTools.append(tool.toOpenAITool())
                }
                logger.debug("Injected \(mcpTools.count) MCP tool(s) into request")
            } catch {
                logger.warn("Failed to list MCP tools: \(error)")
            }
        }

        let frozenTools = allTools
        let frozenMCPToolServerMap = mcpToolServerMap

        let responseStream = AsyncStream<ByteBuffer> { continuation in
            let writer = AgentStreamWriter(
                continuation: continuation,
                completionId: completionId,
                model: model
            )

            let task = Task { [agentLoopService] in
                await agentLoopService.runAgentLoop(
                    request: request,
                    credentials: credentials,
                    allTools: frozenTools,
                    mcpToolServerMap: frozenMCPToolServerMap,
                    writer: writer
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return Response(status: .ok, headers: sseHeaders(), body: .init(asyncSequence: responseStream))
    }

    private func streamForModel(copilotRequest: CopilotChatRequest, credentials: CopilotCredentials) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        var currentRequest = await resolveReasoningEffort(for: copilotRequest)

        for attempt in 0..<Self.maxReasoningEffortRetries {
            do {
                return try await executeStream(copilotRequest: currentRequest, credentials: credentials)
            } catch let error as CopilotAPIError {
                guard case .requestFailed(statusCode: 400, let body) = error,
                      currentRequest.reasoningEffort != nil else {
                    throw error
                }

                let currentEffort = currentRequest.reasoningEffort!
                logger.error("HTTP 400 with reasoning effort '\(currentEffort.rawValue)' for model '\(currentRequest.model)' (attempt \(attempt + 1)/\(Self.maxReasoningEffortRetries)). Error body: \(body)")

                guard let lowerEffort = currentEffort.nextLower else {
                    logger.info("Reasoning effort '\(currentEffort.rawValue)' rejected and no lower level available, retrying without reasoning effort")
                    currentRequest = currentRequest.withReasoningEffort(nil)
                    continue
                }

                logger.info("Downgrading reasoning effort from '\(currentEffort.rawValue)' to '\(lowerEffort.rawValue)' for model '\(currentRequest.model)'")
                await reasoningEffortResolver.recordMaxEffort(lowerEffort, for: currentRequest.model)
                currentRequest = currentRequest.withReasoningEffort(lowerEffort)
            }
        }

        logger.info("Reasoning effort retries exhausted, sending final request with effort: \(currentRequest.reasoningEffort?.rawValue ?? "nil")")
        return try await executeStream(copilotRequest: currentRequest, credentials: credentials)
    }

    private func resolveReasoningEffort(for request: CopilotChatRequest) async -> CopilotChatRequest {
        guard let configured = request.reasoningEffort else { return request }
        let resolved = await reasoningEffortResolver.resolve(configured: configured, for: request.model)
        if resolved != configured {
            logger.info("Clamped reasoning effort from '\(configured.rawValue)' to '\(resolved.rawValue)' for model '\(request.model)'")
        }
        return request.withReasoningEffort(resolved)
    }

    private func executeStream(copilotRequest: CopilotChatRequest, credentials: CopilotCredentials) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let endpoint = await modelEndpointResolver.endpoint(for: copilotRequest.model, credentials: credentials)
        logger.info("Resolved endpoint for model '\(copilotRequest.model)': \(endpoint == .responses ? "responses" : "chatCompletions"), reasoningEffort: \(copilotRequest.reasoningEffort?.rawValue ?? "nil")")

        switch endpoint {
        case .chatCompletions:
            logger.info("Streaming via /chat/completions for model '\(copilotRequest.model)' to \(credentials.apiEndpoint)")
            return try await copilotAPI.streamChatCompletions(request: copilotRequest, credentials: credentials)

        case .responses:
            logger.info("Using Responses API for model: \(copilotRequest.model)")
            let responsesRequest = responsesTranslator.translateRequest(from: copilotRequest)
            logger.debug("Sending Responses API request to endpoint: \(credentials.apiEndpoint)/responses")
            let rawStream = try await copilotAPI.streamResponses(request: responsesRequest, credentials: credentials)
            logger.debug("Responses API raw stream obtained, adapting to chat completions format")
            let completionId = ChatCompletionChunk.makeCompletionId()
            logger.debug("Generated completionId=\(completionId) for adapted stream")
            return responsesTranslator.adaptStream(events: rawStream, completionId: completionId, model: copilotRequest.model)
        }
    }

    private func buildCopilotRequest(from request: ChatCompletionRequest, configuration: ServerConfiguration) -> CopilotChatRequest {
        let tempStr = request.temperature.map { "\($0)" } ?? "nil"
        let topPStr = request.topP.map { "\($0)" } ?? "nil"
        let maxTokensStr = request.maxTokens.map { "\($0)" } ?? "nil"
        logger.info("Building Copilot request: model=\(request.model), messages=\(request.messages.count), tools=\(request.tools?.count ?? 0), reasoningEffort=\(configuration.reasoningEffort?.rawValue ?? "nil"), temperature=\(tempStr), topP=\(topPStr), maxTokens=\(maxTokensStr)")
        return CopilotChatRequest(
            model: request.model,
            messages: request.messages,
            temperature: request.temperature,
            topP: request.topP,
            maxTokens: request.maxTokens,
            stop: request.stop,
            tools: request.tools,
            toolChoice: request.toolChoice,
            reasoningEffort: configuration.reasoningEffort,
            stream: true
        )
    }

    private func sseHeaders() -> HTTPFields {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        headers[HTTPField.Name("X-Accel-Buffering")!] = "no"
        return headers
    }

    private static let maxReasoningEffortRetries = 3
}

private enum ChatCompletionsHandlerError: Error {
    case timeout
}