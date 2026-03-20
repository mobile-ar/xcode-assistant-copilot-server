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

    private static let maxReasoningEffortRetries = 3
    private static let defaultMCPToolTimeoutSeconds: Double = 60

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
    }

    public func handle(request: Request) async throws -> Response {
        let configuration = await configurationStore.current()
        // consumeWithCancellationOnInboundClose monitors the inbound TCP stream.
        // When Xcode hits Stop it closes the connection, which closes the inbound
        // stream and throws CancellationError into the task running this closure,
        // propagating cooperative cancellation to all awaits inside (collectStreamedResponse,
        // executeMCPTool, Task.sleep, etc.).
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

    func handleDirectStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials) async -> Response {
        let configuration = await configurationStore.current()
        return await handleDirectStreaming(request: request, credentials: credentials, configuration: configuration)
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

                        group.addTask { [logger] in
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
                                    let sseData = "data: \(normalizeEventData(event.data))\n\n"
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

    func handleAgentStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials) async -> Response {
        let configuration = await configurationStore.current()
        return await handleAgentStreaming(request: request, credentials: credentials, configuration: configuration)
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

            let task = Task {
                await runAgentLoop(
                    request: request,
                    credentials: credentials,
                    allTools: frozenTools,
                    mcpToolServerMap: frozenMCPToolServerMap,
                    writer: writer,
                    configuration: configuration
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return Response(status: .ok, headers: sseHeaders(), body: .init(asyncSequence: responseStream))
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
        let contextManager = ConversationContextManager(logger: logger)
        var messages = request.messages
        let model = request.model
        var iteration = 0
        var hadToolUse = false

        let preEncodedTools: Data? = preEncodeTools(allTools)
        let toolsTokenEstimate = contextManager.estimateTokenCount(tools: allTools)

        let modelContextWindow = await modelEndpointResolver.contextWindowTokenLimit(for: model, credentials: credentials)
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

            let compactedMessages = contextManager.compact(
                messages: messages,
                tokenLimit: effectiveTokenLimit,
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
                collectedResponse = try await collectStreamedResponse(request: copilotRequest, credentials: credentials)
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
                            toolResult = try await executeMCPTool(toolCall: toolCall, serverName: serverName, configuration: configuration)
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

    func executeMCPTool(toolCall: ToolCall, serverName: String = "") async throws -> String {
        let configuration = await configurationStore.current()
        return try await executeMCPTool(toolCall: toolCall, serverName: serverName, configuration: configuration)
    }

    private func executeMCPTool(toolCall: ToolCall, serverName: String, configuration: ServerConfiguration) async throws -> String {
        guard let mcpBridge = await bridgeHolder.bridge else {
            return "Error: MCP bridge not available"
        }

        let toolName = toolCall.function.name ?? ""

        guard configuration.autoApprovePermissions.isApproved(.mcp) else {
            logger.warn("MCP tool execution not approved for '\(toolName)'")
            return "Error: MCP tool execution is not approved. Add 'mcp' to autoApprovePermissions."
        }

        guard configuration.isMCPToolAllowed(toolName) else {
            logger.warn("MCP tool '\(toolName)' is not in the allowed tools list")
            return "Error: MCP tool '\(toolName)' is not allowed by server configuration"
        }

        let arguments: [String: AnyCodable]
        if let argumentsString = toolCall.function.arguments {
            logger.debug("MCP tool '\(toolName)' raw arguments (\(argumentsString.count) chars): \(argumentsString)")
            if let data = argumentsString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                arguments = parsed.compactMapValues { AnyCodable(fromAny: $0) }
                logger.debug("MCP tool '\(toolName)' parsed \(arguments.count) argument(s): \(arguments.keys.sorted().joined(separator: ", "))")
            } else {
                logger.error("MCP tool '\(toolName)' failed to parse arguments JSON (\(argumentsString.count) chars) — sending empty arguments")
                arguments = [:]
            }
        } else {
            logger.debug("MCP tool '\(toolName)' has no arguments")
            arguments = [:]
        }

        let timeoutSeconds = resolvedMCPToolTimeoutSeconds(serverName: serverName, configuration: configuration)

        do {
            let result = try await callMCPToolWithTimeout(
                bridge: mcpBridge,
                toolName: toolName,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )
            let text = result.textContent

            if TabIdentifierResolver.isTabIdentifierError(text) {
                let filePath = arguments["filePath"]?.stringValue
                    ?? arguments["sourceFilePath"]?.stringValue
                    ?? arguments["path"]?.stringValue

                if let resolvedTab = TabIdentifierResolver.resolve(from: text, filePath: filePath) {
                    logger.debug("MCP tool '\(toolName)' got invalid tabIdentifier — retrying with resolved '\(resolvedTab)'")
                    var fixedArguments = arguments
                    fixedArguments["tabIdentifier"] = AnyCodable(.string(resolvedTab))
                    let retryResult = try await callMCPToolWithTimeout(
                        bridge: mcpBridge,
                        toolName: toolName,
                        arguments: fixedArguments,
                        timeoutSeconds: timeoutSeconds
                    )
                    return retryResult.textContent
                }
            }

            return text
        } catch is CancellationError {
            logger.debug("MCP tool '\(toolName)' cancelled")
            throw CancellationError()
        } catch let error as MCPToolExecutionError {
            switch error {
            case .timedOut(let timedOutToolName, let timedOutSeconds):
                logger.warn("MCP tool '\(timedOutToolName)' timed out after \(timedOutSeconds) seconds")
                return "Error executing tool \(timedOutToolName): timed out after \(timedOutSeconds) seconds"
            }
        } catch {
            logger.error("MCP tool \(toolName) failed: \(error)")
            return "Error executing tool \(toolName): \(error)"
        }
    }

    private func callMCPToolWithTimeout(
        bridge: MCPBridgeServiceProtocol,
        toolName: String,
        arguments: [String: AnyCodable],
        timeoutSeconds: Double
    ) async throws -> MCPToolResult {
        try await withThrowingTaskGroup(of: MCPToolResult.self) { group in
            group.addTask {
                try await bridge.callTool(name: toolName, arguments: arguments)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw MCPToolExecutionError.timedOut(toolName: toolName, timeoutSeconds: timeoutSeconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func resolvedMCPToolTimeoutSeconds(serverName: String, configuration: ServerConfiguration) -> Double {
        guard !serverName.isEmpty,
              let configuredTimeout = configuration.mcpServers[serverName]?.timeoutSeconds,
              configuredTimeout > 0 else {
            return Self.defaultMCPToolTimeoutSeconds
        }
        return configuredTimeout
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

    /// Normalizes a raw SSE data string before forwarding it to Xcode.
    ///   1. Missing "object" field — some upstream models (e.g. Claude via /chat/completions)
    ///      omit it entirely. Xcode's LSP client requires it on every chunk.
    ///   2. Missing "arguments" in a tool_calls[n].function object — the first name-
    ///      announcement delta arrives with only "name" and no "arguments" key, which
    ///      confuses Xcode's streaming parser. It must be present as "".
    func normalizeEventData(_ data: String) -> String {
        let needsObject = !data.contains("\"object\"")
        let hasToolCalls = data.contains("\"tool_calls\"")

        // Fast exit: nothing to patch.
        if !needsObject && !hasToolCalls {
            return data
        }

        // Only the "object" field is missing and there are no tool_calls to inspect. Prepend
        // the key right after the opening brace so the result is still valid JSON without
        // any parse/reserialize overhead.
        if needsObject && !hasToolCalls {
            guard data.hasPrefix("{") else { return data }
            return "{\"object\":\"chat.completion.chunk\"," + data.dropFirst()
        }

        // Full JSON round-trip for tool_calls events (rare — a handful per conversation).
        // This handles both the "object" and "arguments" patch in one pass.
        return normalizeEventDataViaJSON(data, injectObject: needsObject)
    }

    private func normalizeEventDataViaJSON(_ data: String, injectObject: Bool) -> String {
        guard let jsonData = data.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return data
        }

        if injectObject {
            json["object"] = "chat.completion.chunk"
        }

        if let choices = json["choices"] as? [[String: Any]] {
            json["choices"] = choices.map { choice -> [String: Any] in
                var choice = choice
                if var delta = choice["delta"] as? [String: Any],
                   let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                    delta["tool_calls"] = toolCalls.map { toolCall -> [String: Any] in
                        var toolCall = toolCall
                        if var function = toolCall["function"] as? [String: Any],
                           function["arguments"] == nil {
                            function["arguments"] = ""
                            toolCall["function"] = function
                        }
                        return toolCall
                    }
                    choice["delta"] = delta
                }
                return choice
            }
        }

        guard let normalized = try? JSONSerialization.data(withJSONObject: json),
              let result = String(data: normalized, encoding: .utf8) else {
            return data
        }
        return result
    }

    private func sseHeaders() -> HTTPFields {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        headers[HTTPField.Name("X-Accel-Buffering")!] = "no"
        return headers
    }
}

private enum MCPToolExecutionError: Error {
    case timedOut(toolName: String, timeoutSeconds: Double)
}

private enum ChatCompletionsHandlerError: Error {
    case timeout
}

private struct CollectedResponse: Sendable {
    let content: String
    let toolCalls: [ToolCall]
}

private struct ToolCallBuilder {
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
