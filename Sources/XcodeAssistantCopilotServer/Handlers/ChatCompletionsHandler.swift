import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct ChatCompletionsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let mcpBridge: MCPBridgeServiceProtocol?
    private let modelEndpointResolver: ModelEndpointResolverProtocol
    private let reasoningEffortResolver: ReasoningEffortResolverProtocol
    private let responsesTranslator: ResponsesAPITranslator
    private let configuration: ServerConfiguration
    private let logger: LoggerProtocol

    private static let maxAgentLoopIterations = 20
    private static let maxReasoningEffortRetries = 3

    public init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        mcpBridge: MCPBridgeServiceProtocol?,
        modelEndpointResolver: ModelEndpointResolverProtocol,
        reasoningEffortResolver: ReasoningEffortResolverProtocol,
        configuration: ServerConfiguration,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.mcpBridge = mcpBridge
        self.modelEndpointResolver = modelEndpointResolver
        self.reasoningEffortResolver = reasoningEffortResolver
        self.responsesTranslator = ResponsesAPITranslator(logger: logger)
        self.configuration = configuration
        self.logger = logger
    }

    public func handle(request: Request) async throws -> Response {
        // consumeWithCancellationOnInboundClose monitors the inbound TCP stream.
        // When Xcode hits Stop it closes the connection, which closes the inbound
        // stream and throws CancellationError into the task running this closure,
        // propagating cooperative cancellation to all awaits inside (collectStreamedResponse,
        // executeMCPTool, Task.sleep, etc.).
        do {
            return try await request.body.consumeWithCancellationOnInboundClose { body in
            let bodyBuffer = try await body.collect(upTo: self.configuration.bodyLimitBytes)

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

            if self.mcpBridge != nil {
                return await self.handleAgentStreaming(request: completionRequest, credentials: credentials)
            } else {
                return await self.handleDirectStreaming(request: completionRequest, credentials: credentials)
            }
        }
        } catch is CancellationError {
            logger.info("Request cancelled — user stopped the request from Xcode.")
            throw CancellationError()
        }
    }

    func handleDirectStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials) async -> Response {
        let copilotRequest = buildCopilotRequest(from: request)

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
                        group.addTask {
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
        let completionId = ChatCompletionChunk.makeCompletionId()
        let model = request.model

        var mcpToolNames: Set<String> = []
        var allTools = request.tools ?? []

        if let mcpBridge {
            do {
                let mcpTools = try await mcpBridge.listTools()
                for tool in mcpTools {
                    mcpToolNames.insert(tool.name)
                    allTools.append(tool.toOpenAITool())
                }
                logger.debug("Injected \(mcpTools.count) MCP tool(s) into request")
            } catch {
                logger.warn("Failed to list MCP tools: \(error)")
            }
        }

        let frozenTools = allTools
        let frozenMCPToolNames = mcpToolNames

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
                    mcpToolNames: frozenMCPToolNames,
                    writer: writer
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
        mcpToolNames: Set<String>,
        writer: some AgentStreamWriterProtocol
    ) async {
        let formatter = AgentProgressFormatter()
        var messages = request.messages
        let model = request.model
        var iteration = 0
        var hadToolUse = false

        writer.writeRoleDelta()


        while iteration < Self.maxAgentLoopIterations {
            guard !Task.isCancelled else {
                logger.debug("Agent loop cancelled before iteration \(iteration + 1)")
                writer.finish()
                return
            }
            iteration += 1
            logger.debug("Agent loop iteration \(iteration)")

            let copilotRequest = CopilotChatRequest(
                model: model,
                messages: messages,
                temperature: request.temperature,
                topP: request.topP,
                maxTokens: request.maxTokens,
                stop: request.stop,
                tools: allTools.isEmpty ? nil : allTools,
                toolChoice: request.toolChoice,
                reasoningEffort: configuration.reasoningEffort,
                stream: true
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
                let mcpCalls = responseToolCalls.filter { mcpToolNames.contains($0.function.name ?? "") }
                let otherCalls = responseToolCalls.filter { !mcpToolNames.contains($0.function.name ?? "") }

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

                        let toolResult: String
                        do {
                            toolResult = try await executeMCPTool(toolCall: toolCall)
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

        logger.warn("Agent loop hit maximum iterations (\(Self.maxAgentLoopIterations))")
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

    func executeMCPTool(toolCall: ToolCall) async throws -> String {
        guard let mcpBridge else {
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

        do {
            let result = try await mcpBridge.callTool(name: toolName, arguments: arguments)
            let text = result.textContent

            if TabIdentifierResolver.isTabIdentifierError(text) {
                let filePath = arguments["filePath"]?.stringValue
                    ?? arguments["sourceFilePath"]?.stringValue
                    ?? arguments["path"]?.stringValue

                if let resolvedTab = TabIdentifierResolver.resolve(from: text, filePath: filePath) {
                    logger.debug("MCP tool '\(toolName)' got invalid tabIdentifier — retrying with resolved '\(resolvedTab)'")
                    var fixedArguments = arguments
                    fixedArguments["tabIdentifier"] = AnyCodable(.string(resolvedTab))
                    let retryResult = try await mcpBridge.callTool(name: toolName, arguments: fixedArguments)
                    return retryResult.textContent
                }
            }

            return text
        } catch is CancellationError {
            logger.debug("MCP tool '\(toolName)' cancelled")
            throw CancellationError()
        } catch {
            logger.error("MCP tool \(toolName) failed: \(error)")
            return "Error executing tool \(toolName): \(error)"
        }
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

    private func buildCopilotRequest(from request: ChatCompletionRequest) -> CopilotChatRequest {
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

    func normalizeEventData(_ data: String) -> String {
        guard let jsonData = data.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return data
        }
        if json["object"] == nil {
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

private enum ChatCompletionsHandlerError: Error {
    case timeout
}

private struct CollectedResponse: Sendable {
    let content: String
    let toolCalls: [ToolCall]
}

private final class ToolCallBuilder {
    var id: String?
    var type: String?
    var index: Int?
    var functionName: String = ""
    var functionArguments: String = ""

    func merge(_ delta: ToolCall) {
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
