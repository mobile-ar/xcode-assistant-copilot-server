import Foundation

protocol AgentLoopServiceProtocol: Sendable {
    func runAgentLoop(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials,
        allTools: [Tool],
        mcpToolServerMap: [String: String],
        writer: some AgentStreamWriterProtocol
    ) async
}

struct AgentLoopService: AgentLoopServiceProtocol, Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let mcpToolExecutor: MCPToolExecutorProtocol
    private let modelEndpointResolver: ModelEndpointResolverProtocol
    private let reasoningEffortResolver: ReasoningEffortResolverProtocol
    private let responsesTranslator: ResponsesAPITranslator
    private let configurationStore: ConfigurationStore
    private let logger: LoggerProtocol

    private static let maxReasoningEffortRetries = 3

    init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        mcpToolExecutor: MCPToolExecutorProtocol,
        modelEndpointResolver: ModelEndpointResolverProtocol,
        reasoningEffortResolver: ReasoningEffortResolverProtocol,
        responsesTranslator: ResponsesAPITranslator,
        configurationStore: ConfigurationStore,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.mcpToolExecutor = mcpToolExecutor
        self.modelEndpointResolver = modelEndpointResolver
        self.reasoningEffortResolver = reasoningEffortResolver
        self.responsesTranslator = responsesTranslator
        self.configurationStore = configurationStore
        self.logger = logger
    }

    func runAgentLoop(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials,
        allTools: [Tool],
        mcpToolServerMap: [String: String],
        writer: some AgentStreamWriterProtocol
    ) async {
        let configuration = await configurationStore.current()
        await runAgentLoop(
            request: request,
            credentials: credentials,
            allTools: allTools,
            mcpToolServerMap: mcpToolServerMap,
            writer: writer,
            configuration: configuration
        )
    }

    private func runAgentLoop(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials,
        allTools: [Tool],
        mcpToolServerMap: [String: String],
        writer: some AgentStreamWriterProtocol,
        configuration: ServerConfiguration
    ) async {
        let formatter = AgentProgressFormatter()
        var currentCredentials = credentials
        let contextManager = ConversationContextManager(logger: logger)
        var messages = request.messages
        let model = request.model
        var iteration = 0
        var hadToolUse = false

        let preEncodedTools: Data? = preEncodeTools(allTools)
        let toolsTokenEstimate = contextManager.estimateTokenCount(tools: allTools)

        let modelContextWindow = await modelEndpointResolver.contextWindowTokenLimit(for: model, credentials: currentCredentials)
        let effectiveTokenLimit = modelContextWindow ?? 128_000
        if let modelContextWindow {
            logger.info("Using model-specific context window for '\(model)': \(modelContextWindow) tokens")
        } else {
            logger.info("No model-specific context window for '\(model)', using default: 128000 tokens")
        }

        writer.writeRoleDelta()

        while iteration < configuration.maxAgentLoopIterations {
            guard !Task.isCancelled else {
                logger.debug("Agent loop cancelled before iteration \(iteration + 1)")
                writer.finish()
                return
            }
            iteration += 1
            logger.debug("Agent loop iteration \(iteration)")

            let availableForMessages = max(0, effectiveTokenLimit - toolsTokenEstimate)
            let compactedMessages = contextManager.compact(
                messages: messages,
                tokenLimit: availableForMessages,
                recencyWindow: configuration.contextRecencyWindow
            )

            let messagesTokenEstimate = contextManager.estimateTokenCount(messages: compactedMessages)
            let totalTokenEstimate = messagesTokenEstimate + toolsTokenEstimate
            let usagePercent = effectiveTokenLimit > 0 ? totalTokenEstimate * 100 / effectiveTokenLimit : 0

            logger.info("Current token usage \(totalTokenEstimate)/\(effectiveTokenLimit) (\(usagePercent)%)")
            if usagePercent > 80 {
                logger.warn("Agent loop iteration \(iteration): token usage exceeding 80% of context window")
            }

            let copilotRequest = CopilotChatRequest(
                model: model,
                messages: compactedMessages,
                temperature: request.temperature,
                topP: request.topP,
                maxTokens: request.maxTokens,
                stop: request.stop,
                tools: allTools.isEmpty ? nil : allTools,
                toolChoice: request.toolChoice,
                reasoningEffort: configuration.reasoningEffort,
                stream: true,
                preEncodedTools: preEncodedTools
            )

            let collectedResponse: CollectedResponse
            do {
                collectedResponse = try await collectStreamedResponse(request: copilotRequest, credentials: currentCredentials)
            } catch CopilotAPIError.unauthorized {
                logger.warn("Token expired at agent loop iteration \(iteration), refreshing credentials")
                do {
                    await authService.invalidateCachedToken()
                    currentCredentials = try await authService.getValidCopilotToken()
                    collectedResponse = try await collectStreamedResponse(request: copilotRequest, credentials: currentCredentials)
                } catch is CancellationError {
                    logger.debug("Agent loop cancelled during auth retry at iteration \(iteration)")
                    writer.finish()
                    return
                } catch {
                    logger.error("Auth retry failed at agent loop iteration \(iteration): \(error)")
                    writer.writeProgressText("\n> **✗** Authentication failed: \(error)\n")
                    writer.finish()
                    return
                }
            } catch is CancellationError {
                logger.debug("Agent loop cancelled at iteration \(iteration)")
                writer.finish()
                return
            } catch {
                logger.error("Agent loop failed at iteration \(iteration): \(error)")
                writer.writeProgressText("\n> **✗** Streaming failed: \(error)\n")
                writer.finish()
                return
            }

            let responseToolCalls = collectedResponse.toolCalls
            let responseContent = collectedResponse.content

            if !responseToolCalls.isEmpty {
                let mcpCalls = responseToolCalls.filter { mcpToolServerMap[$0.function.name ?? ""] != nil }
                let otherCalls = responseToolCalls.filter { mcpToolServerMap[$0.function.name ?? ""] == nil }

                let shellApproved = configuration.autoApprovePermissions.isApproved(.shell)
                let allowedCliCalls = otherCalls.filter { shellApproved && configuration.isCliToolAllowed($0.function.name ?? "") }
                let blockedCliCalls = otherCalls.filter { !shellApproved || !configuration.isCliToolAllowed($0.function.name ?? "") }

                let hasServerSideWork = !mcpCalls.isEmpty || !blockedCliCalls.isEmpty

                if hasServerSideWork {
                    if !mcpCalls.isEmpty {
                        logger.info("Executing \(mcpCalls.count) MCP tool call(s)")
                    }
                    if !blockedCliCalls.isEmpty {
                        logger.info("Blocking \(blockedCliCalls.count) disallowed CLI tool call(s)")
                    }

                    let assistantMessage = ChatCompletionMessage(
                        role: .assistant,
                        content: responseContent.isEmpty ? nil : .text(responseContent),
                        toolCalls: responseToolCalls
                    )
                    messages.append(assistantMessage)

                    for toolCall in mcpCalls {
                        hadToolUse = true
                        writer.writeProgressText(formatter.formattedToolCall(toolCall))

                        let serverName = mcpToolServerMap[toolCall.function.name ?? ""] ?? ""
                        let toolResult: String
                        do {
                            toolResult = try await mcpToolExecutor.execute(toolCall: toolCall, serverName: serverName)
                        } catch is CancellationError {
                            logger.debug("Agent loop cancelled during MCP tool execution")
                            writer.finish()
                            return
                        } catch {
                            toolResult = "Error executing tool \(toolCall.function.name ?? ""): \(error)"
                        }

                        let formattedResult = formatter.formattedToolResult(toolResult)
                        if !formattedResult.isEmpty {
                            writer.writeProgressText(formattedResult)
                        }

                        let toolMessage = ChatCompletionMessage(
                            role: .tool,
                            content: .text(toolResult),
                            toolCallId: toolCall.id
                        )
                        messages.append(toolMessage)
                    }

                    for blocked in blockedCliCalls {
                        hadToolUse = true
                        let reason = shellApproved ? "Tool '\(blocked.function.name ?? "")' is not in the allowed CLI tools list." : "Shell tool execution is not approved. Add 'shell' to autoApprovePermissions."
                        logger.warn("CLI tool '\(blocked.function.name ?? "")' blocked: \(reason)")
                        writer.writeProgressText(formatter.formattedToolCall(blocked))
                        writer.writeProgressText("\n> **✗** \(reason)\n")
                        let toolMessage = ChatCompletionMessage(
                            role: .tool,
                            content: .text("Error: \(reason)"),
                            toolCallId: blocked.id
                        )
                        messages.append(toolMessage)
                    }

                    if !allowedCliCalls.isEmpty {
                        logger.info("Agent loop completed after \(iteration) iteration(s), returning \(allowedCliCalls.count) allowed CLI tool call(s) to client")
                        writer.writeFinalContent(responseContent, toolCalls: allowedCliCalls, hadToolUse: hadToolUse)
                        writer.finish()
                        return
                    }

                    if !blockedCliCalls.isEmpty && mcpCalls.isEmpty {
                        logger.info("All CLI tool calls blocked, continuing agent loop")
                    } else if !blockedCliCalls.isEmpty {
                        logger.info("MCP tool(s) executed and CLI tool calls blocked, continuing agent loop")
                    } else {
                        logger.info("MCP tool(s) executed, continuing agent loop")
                    }
                    continue
                } else {
                    logger.info("Agent loop completed after \(iteration) iteration(s), streaming buffered response with tool calls")
                    writer.writeFinalContent(responseContent, toolCalls: responseToolCalls, hadToolUse: hadToolUse)
                    writer.finish()
                    return
                }
            } else {
                logger.info("Agent loop completed after \(iteration) iteration(s), streaming buffered response")
                writer.writeFinalContent(responseContent, toolCalls: nil, hadToolUse: hadToolUse)
                writer.finish()
                return
            }
        }

        logger.warn("Agent loop hit maximum iterations (\(configuration.maxAgentLoopIterations))")
        writer.writeFinalContent("", toolCalls: nil, hadToolUse: hadToolUse)
        writer.finish()
    }

    private func collectStreamedResponse(request: CopilotChatRequest, credentials: CopilotCredentials) async throws -> CollectedResponse {
        let eventStream = try await streamForModel(copilotRequest: request, credentials: credentials)

        var content = ""
        var toolCalls: [ToolCall] = []
        var toolCallBuilders: [Int: ToolCallBuilder] = [:]

        for try await event in eventStream {
            try Task.checkCancellation()

            if event.isDone { break }

            let chunk: ChatCompletionChunk
            do {
                chunk = try event.decodeData(ChatCompletionChunk.self)
            } catch {
                logger.debug("Failed to decode chunk (\(error)): \(event.data)")
                continue
            }

            guard let choice = chunk.choices.first else { continue }

            if let delta = choice.delta {
                if let deltaContent = delta.content {
                    content += deltaContent
                }

                if let deltaToolCalls = delta.toolCalls {
                    for tc in deltaToolCalls {
                        let index = tc.index ?? 0
                        if toolCallBuilders[index] == nil {
                            toolCallBuilders[index] = ToolCallBuilder()
                        }
                        toolCallBuilders[index]?.merge(tc)
                    }
                }
            }

            if choice.finishReason != nil {
                break
            }
        }

        for (_, builder) in toolCallBuilders.sorted(by: { $0.key < $1.key }) {
            if let toolCall = builder.build() {
                let argsLength = toolCall.function.arguments?.count ?? 0
                logger.debug("collectStreamedResponse: built tool call '\(toolCall.function.name ?? "")' id=\(toolCall.id ?? "nil") argsLength=\(argsLength)")
                toolCalls.append(toolCall)
            }
        }

        logger.debug("collectStreamedResponse: finished — content=\(content.count) chars, toolCalls=\(toolCalls.count), builders=\(toolCallBuilders.count)")
        return CollectedResponse(content: content, toolCalls: toolCalls)
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

    private func preEncodeTools(_ tools: [Tool]) -> Data? {
        guard !tools.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let data = try encoder.encode(tools)
            logger.debug("Pre-encoded \(tools.count) tool definition(s) (\(data.count) bytes)")
            return data
        } catch {
            logger.warn("Failed to pre-encode tools, will re-encode per iteration: \(error)")
            return nil
        }
    }
}

struct CollectedResponse: Sendable {
    let content: String
    let toolCalls: [ToolCall]
}

struct ToolCallBuilder {
    var id: String?
    var type: String?
    var index: Int?
    var functionName: String = ""
    var functionArguments: String = ""

    mutating func merge(_ delta: ToolCall) {
        if let deltaId = delta.id {
            id = deltaId
        }
        if let deltaType = delta.type {
            type = deltaType
        }
        if let deltaIndex = delta.index {
            index = deltaIndex
        }
        functionName += delta.function.name ?? ""
        functionArguments += delta.function.arguments ?? ""
    }

    func build() -> ToolCall? {
        guard !functionName.isEmpty else { return nil }
        return ToolCall(
            index: index,
            id: id,
            type: type ?? "function",
            function: ToolCallFunction(
                name: functionName,
                arguments: functionArguments
            )
        )
    }
}