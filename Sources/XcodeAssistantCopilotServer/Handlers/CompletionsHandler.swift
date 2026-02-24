import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct CompletionsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let mcpBridge: MCPBridgeServiceProtocol?
    private let modelEndpointResolver: ModelEndpointResolverProtocol
    private let reasoningEffortResolver: ReasoningEffortResolverProtocol
    private let responsesTranslator: ResponsesAPITranslator
    private let configuration: ServerConfiguration
    private let logger: LoggerProtocol

    private static let requestTimeoutSeconds: UInt64 = 5 * 60
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

    public func handle(request: Request, context: some RequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: configuration.bodyLimitBytes)

        let completionRequest: ChatCompletionRequest
        do {
            completionRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        } catch {
            logger.warn("Invalid request body: \(error)")
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
            credentials = try await authService.getValidCopilotToken()
        } catch {
            logger.error("Authentication failed: \(error)")
            return ErrorResponseBuilder.build(status: .unauthorized, type: "api_error", message: "Authentication failed: \(error)")
        }

        if mcpBridge != nil {
            return await handleAgentStreaming(request: completionRequest, credentials: credentials)
        } else {
            return await handleDirectStreaming(request: completionRequest, credentials: credentials)
        }
    }

    private func handleDirectStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials) async -> Response {
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
            Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                            throw CompletionsHandlerError.timeout
                        }

                        group.addTask { [logger] in
                            var forwardedEventCount = 0
                            do {
                                for try await event in eventStream {
                                    if Task.isCancelled {
                                        logger.debug("Direct stream: task cancelled after \(forwardedEventCount) forwarded events")
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
                                        logger.debug("Direct stream: forwarding event #\(forwardedEventCount), data length=\(event.data.count), preview=\(event.data.prefix(150))")
                                    }
                                    let sseData = "data: \(event.data)\n\n"
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
                    if error is CompletionsHandlerError {
                        logger.warn("Stream timed out after \(Self.requestTimeoutSeconds) seconds")
                    }
                    continuation.finish()
                }
            }
        }

        return Response(status: .ok, headers: sseHeaders(), body: .init(asyncSequence: responseStream))
    }

    func handleAgentStreaming(request: ChatCompletionRequest, credentials: CopilotCredentials) async -> Response {
        let completionId = ChatCompletionChunk.makeCompletionId()
        var messages = request.messages
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

        var iteration = 0

        while iteration < Self.maxAgentLoopIterations {
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
                collectedResponse = try await collectStreamedResponse(request: copilotRequest, credentials: credentials, model: model)
            } catch {
                logger.error("Agent loop failed at iteration \(iteration): \(error)")
                return ErrorResponseBuilder.build(status: .internalServerError, type: "api_error", message: "Streaming failed: \(error)")
            }

            let responseToolCalls = collectedResponse.toolCalls
            let responseContent = collectedResponse.content

            if !responseToolCalls.isEmpty {
                let mcpCalls = responseToolCalls.filter { mcpToolNames.contains($0.function.name) }
                let otherCalls = responseToolCalls.filter { !mcpToolNames.contains($0.function.name) }

                let shellApproved = configuration.autoApprovePermissions.isApproved(.shell)
                let allowedCliCalls = otherCalls.filter { shellApproved && configuration.isCliToolAllowed($0.function.name) }
                let blockedCliCalls = otherCalls.filter { !shellApproved || !configuration.isCliToolAllowed($0.function.name) }

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
                        let toolResult = await executeMCPTool(toolCall: toolCall)
                        let toolMessage = ChatCompletionMessage(
                            role: .tool,
                            content: .text(toolResult),
                            toolCallId: toolCall.id
                        )
                        messages.append(toolMessage)
                    }

                    for blocked in blockedCliCalls {
                        let reason = shellApproved ? "Tool '\(blocked.function.name)' is not in the allowed CLI tools list." : "Shell tool execution is not approved. Add 'shell' to autoApprovePermissions."
                        logger.warn("CLI tool '\(blocked.function.name)' blocked: \(reason)")
                        let toolMessage = ChatCompletionMessage(
                            role: .tool,
                            content: .text("Error: \(reason)"),
                            toolCallId: blocked.id
                        )
                        messages.append(toolMessage)
                    }

                    if !allowedCliCalls.isEmpty {
                        logger.info("Agent loop completed after \(iteration) iteration(s), returning \(allowedCliCalls.count) allowed CLI tool call(s) to client")
                        return buildBufferedStreamingResponse(
                            completionId: completionId,
                            model: model,
                            content: responseContent,
                            toolCalls: allowedCliCalls
                        )
                    }

                    if !blockedCliCalls.isEmpty {
                        logger.info("All CLI tool calls blocked, continuing agent loop")
                        continue
                    }

                    logger.info("MCP tool(s) executed, streaming final response directly")
                    return await streamFinalAgentResponse(
                        request: request,
                        credentials: credentials,
                        messages: messages,
                        model: model,
                        allTools: allTools
                    )
                } else {
                    logger.info("Agent loop completed after \(iteration) iteration(s), streaming buffered response with tool calls")
                    return buildBufferedStreamingResponse(
                        completionId: completionId,
                        model: model,
                        content: responseContent,
                        toolCalls: responseToolCalls
                    )
                }
            } else {
                logger.info("Agent loop completed after \(iteration) iteration(s), streaming buffered response")
                return buildBufferedStreamingResponse(
                    completionId: completionId,
                    model: model,
                    content: responseContent,
                    toolCalls: nil
                )
            }
        }

        logger.warn("Agent loop hit maximum iterations (\(Self.maxAgentLoopIterations))")
        return buildBufferedStreamingResponse(
            completionId: completionId,
            model: model,
            content: "",
            toolCalls: nil
        )
    }

    private func streamFinalAgentResponse(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials,
        messages: [ChatCompletionMessage],
        model: String,
        allTools: [Tool]
    ) async -> Response {
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

        let eventStream: AsyncThrowingStream<SSEEvent, Error>
        do {
            eventStream = try await streamForModel(copilotRequest: copilotRequest, credentials: credentials)
        } catch {
            logger.error("Copilot API streaming failed for final agent response: \(error)")
            return ErrorResponseBuilder.build(status: .internalServerError, type: "api_error", message: "Failed to start streaming: \(error)")
        }

        logger.info("Streaming final agent response directly")

        let responseStream = AsyncStream<ByteBuffer> { continuation in
            Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                            throw CompletionsHandlerError.timeout
                        }

                        group.addTask { [logger] in
                            do {
                                for try await event in eventStream {
                                    if Task.isCancelled { break }

                                    if event.isDone {
                                        let doneBuffer = ByteBuffer(string: "data: [DONE]\n\n")
                                        continuation.yield(doneBuffer)
                                        break
                                    }

                                    let sseData = "data: \(event.data)\n\n"
                                    let buffer = ByteBuffer(string: sseData)
                                    continuation.yield(buffer)
                                }
                            } catch {
                                logger.error("Stream error: \(error)")
                            }
                            continuation.finish()
                        }

                        try await group.next()
                        group.cancelAll()
                    }
                } catch {
                    if error is CompletionsHandlerError {
                        logger.warn("Stream timed out after \(Self.requestTimeoutSeconds) seconds")
                    }
                    continuation.finish()
                }
            }
        }

        return Response(status: .ok, headers: sseHeaders(), body: .init(asyncSequence: responseStream))
    }

    private func collectStreamedResponse(request: CopilotChatRequest, credentials: CopilotCredentials, model: String) async throws -> CollectedResponse {
        let eventStream = try await streamForModel(copilotRequest: request, credentials: credentials)

        var content = ""
        var toolCalls: [ToolCall] = []
        var toolCallBuilders: [Int: ToolCallBuilder] = [:]

        for try await event in eventStream {
            if event.isDone { break }

            let chunk: ChatCompletionChunk
            do {
                chunk = try event.decodeData(ChatCompletionChunk.self)
            } catch {
                logger.debug("Failed to decode chunk: \(event.data.prefix(200))")
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
                toolCalls.append(toolCall)
            }
        }

        return CollectedResponse(content: content, toolCalls: toolCalls)
    }

    func executeMCPTool(toolCall: ToolCall) async -> String {
        guard let mcpBridge else {
            return "Error: MCP bridge not available"
        }

        guard configuration.autoApprovePermissions.isApproved(.mcp) else {
            logger.warn("MCP tool execution not approved for '\(toolCall.function.name)'")
            return "Error: MCP tool execution is not approved. Add 'mcp' to autoApprovePermissions."
        }

        guard configuration.isMCPToolAllowed(toolCall.function.name) else {
            logger.warn("MCP tool '\(toolCall.function.name)' is not in the allowed tools list")
            return "Error: MCP tool '\(toolCall.function.name)' is not allowed by server configuration"
        }

        let arguments: [String: AnyCodable]
        if let data = toolCall.function.arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = parsed.compactMapValues { AnyCodable(fromAny: $0) }
        } else {
            arguments = [:]
        }

        do {
            let result = try await mcpBridge.callTool(
                name: toolCall.function.name,
                arguments: arguments
            )
            return result.textContent
        } catch {
            logger.error("MCP tool \(toolCall.function.name) failed: \(error)")
            return "Error executing tool \(toolCall.function.name): \(error)"
        }
    }

    private func buildBufferedStreamingResponse(
        completionId: String,
        model: String,
        content: String,
        toolCalls: [ToolCall]?
    ) -> Response {
        let responseStream = AsyncStream<ByteBuffer> { continuation in
            let encoder = JSONEncoder()

            let roleChunk = ChatCompletionChunk.makeRoleDelta(id: completionId, model: model)
            if let data = try? encoder.encode(roleChunk),
               let jsonString = String(data: data, encoding: .utf8) {
                continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
            }

            if !content.isEmpty {
                let contentChunk = ChatCompletionChunk.makeContentDelta(
                    id: completionId,
                    model: model,
                    content: content
                )
                if let data = try? encoder.encode(contentChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }
            }

            if let toolCalls, !toolCalls.isEmpty {
                let toolCallChunk = ChatCompletionChunk.makeToolCallDelta(
                    id: completionId,
                    model: model,
                    toolCalls: toolCalls
                )
                if let data = try? encoder.encode(toolCallChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }

                let finishChunk = ChatCompletionChunk(
                    id: completionId,
                    model: model,
                    choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "tool_calls")]
                )
                if let data = try? encoder.encode(finishChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }
            } else {
                let stopChunk = ChatCompletionChunk.makeStopDelta(id: completionId, model: model)
                if let data = try? encoder.encode(stopChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }
            }

            continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
            continuation.finish()
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
                      let currentEffort = currentRequest.reasoningEffort,
                      body.contains(currentEffort.rawValue) else {
                    throw error
                }

                guard let lowerEffort = currentEffort.nextLower else {
                    logger.warn("Reasoning effort '\(currentEffort.rawValue)' rejected and no lower level available, retrying without reasoning effort")
                    currentRequest = currentRequest.withReasoningEffort(nil)
                    continue
                }

                logger.info("Reasoning effort '\(currentEffort.rawValue)' not supported by model '\(currentRequest.model)', retrying with '\(lowerEffort.rawValue)' (attempt \(attempt + 1))")
                await reasoningEffortResolver.recordMaxEffort(lowerEffort, for: currentRequest.model)
                currentRequest = currentRequest.withReasoningEffort(lowerEffort)
            }
        }

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

        switch endpoint {
        case .chatCompletions:
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
        CopilotChatRequest(
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
}

private enum CompletionsHandlerError: Error {
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
        functionName += delta.function.name
        functionArguments += delta.function.arguments
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
