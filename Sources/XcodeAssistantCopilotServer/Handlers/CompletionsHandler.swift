import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct CompletionsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let mcpBridge: MCPBridgeServiceProtocol?
    private let configuration: ServerConfiguration
    private let logger: LoggerProtocol
    private let promptFormatter: PromptFormatter

    private static let requestTimeoutSeconds: UInt64 = 5 * 60
    private static let maxAgentLoopIterations = 20

    public init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        mcpBridge: MCPBridgeServiceProtocol?,
        configuration: ServerConfiguration,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.mcpBridge = mcpBridge
        self.configuration = configuration
        self.logger = logger
        self.promptFormatter = PromptFormatter()
    }

    public func handle(request: Request, context: some RequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: configuration.bodyLimitBytes)

        let completionRequest: ChatCompletionRequest
        do {
            completionRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        } catch {
            logger.warn("Invalid request body: \(error)")
            return errorResponse(
                status: .badRequest,
                type: "invalid_request_error",
                message: "Invalid request body: \(error)"
            )
        }

        guard !completionRequest.model.isEmpty else {
            return errorResponse(
                status: .badRequest,
                type: "invalid_request_error",
                message: "Model is required"
            )
        }

        guard !completionRequest.messages.isEmpty else {
            return errorResponse(
                status: .badRequest,
                type: "invalid_request_error",
                message: "Messages are required"
            )
        }

        let credentials: CopilotCredentials
        do {
            credentials = try await authService.getValidCopilotToken()
        } catch {
            logger.error("Authentication failed: \(error)")
            return errorResponse(
                status: .unauthorized,
                type: "api_error",
                message: "Authentication failed: \(error)"
            )
        }

        if mcpBridge != nil {
            return await handleAgentStreaming(
                request: completionRequest,
                credentials: credentials
            )
        } else {
            return await handleDirectStreaming(
                request: completionRequest,
                credentials: credentials
            )
        }
    }

    private func handleDirectStreaming(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials
    ) async -> Response {
        let copilotRequest = buildCopilotRequest(from: request)

        let eventStream: AsyncThrowingStream<SSEEvent, Error>
        do {
            eventStream = try await copilotAPI.streamChatCompletions(
                request: copilotRequest,
                credentials: credentials
            )
        } catch {
            logger.error("Copilot API streaming failed: \(error)")
            return errorResponse(
                status: .internalServerError,
                type: "api_error",
                message: "Failed to start streaming: \(error)"
            )
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

                        if let firstResult = try await group.next() {
                            _ = firstResult
                        }
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

        return Response(
            status: .ok,
            headers: sseHeaders(),
            body: .init(asyncSequence: responseStream)
        )
    }

    private func handleAgentStreaming(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials
    ) async -> Response {
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
        var finalContent = ""
        var finalToolCalls: [ToolCall]?

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
                collectedResponse = try await collectStreamedResponse(
                    request: copilotRequest,
                    credentials: credentials,
                    model: model
                )
            } catch {
                logger.error("Agent loop failed at iteration \(iteration): \(error)")
                return errorResponse(
                    status: .internalServerError,
                    type: "api_error",
                    message: "Streaming failed: \(error)"
                )
            }

            let responseToolCalls = collectedResponse.toolCalls
            let responseContent = collectedResponse.content

            if !responseToolCalls.isEmpty {
                let mcpCalls = responseToolCalls.filter { mcpToolNames.contains($0.function.name) }
                let otherCalls = responseToolCalls.filter { !mcpToolNames.contains($0.function.name) }

                if !mcpCalls.isEmpty {
                    logger.info("Executing \(mcpCalls.count) MCP tool call(s)")

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

                    if !otherCalls.isEmpty {
                        finalContent = responseContent
                        finalToolCalls = otherCalls
                        break
                    }

                    continue
                } else {
                    finalContent = responseContent
                    finalToolCalls = responseToolCalls
                    break
                }
            } else {
                finalContent = responseContent
                finalToolCalls = nil
                break
            }
        }

        if iteration >= Self.maxAgentLoopIterations {
            logger.warn("Agent loop hit maximum iterations (\(Self.maxAgentLoopIterations))")
        }

        logger.info("Agent loop completed after \(iteration) iteration(s), streaming response")
        return buildStreamingResponse(
            completionId: completionId,
            model: model,
            content: finalContent,
            toolCalls: finalToolCalls
        )
    }

    private func collectStreamedResponse(
        request: CopilotChatRequest,
        credentials: CopilotCredentials,
        model: String
    ) async throws -> CollectedResponse {
        let eventStream = try await copilotAPI.streamChatCompletions(
            request: request,
            credentials: credentials
        )

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

    private func executeMCPTool(toolCall: ToolCall) async -> String {
        guard let mcpBridge else {
            return "Error: MCP bridge not available"
        }

        let arguments: [String: AnyCodable]
        if let data = toolCall.function.arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = parsed.compactMapValues { anyToAnyCodable($0) }
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

    private func buildStreamingResponse(
        completionId: String,
        model: String,
        content: String,
        toolCalls: [ToolCall]?
    ) -> Response {
        let responseStream = AsyncStream<ByteBuffer> { continuation in
            let roleChunk = ChatCompletionChunk.makeRoleDelta(id: completionId, model: model)
            if let data = try? JSONEncoder().encode(roleChunk),
               let jsonString = String(data: data, encoding: .utf8) {
                continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
            }

            if !content.isEmpty {
                let chunkSize = 20
                var index = content.startIndex
                while index < content.endIndex {
                    let end = content.index(index, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
                    let piece = String(content[index..<end])

                    let contentChunk = ChatCompletionChunk.makeContentDelta(
                        id: completionId,
                        model: model,
                        content: piece
                    )
                    if let data = try? JSONEncoder().encode(contentChunk),
                       let jsonString = String(data: data, encoding: .utf8) {
                        continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                    }

                    index = end
                }
            }

            if let toolCalls, !toolCalls.isEmpty {
                let toolCallChunk = ChatCompletionChunk.makeToolCallDelta(
                    id: completionId,
                    model: model,
                    toolCalls: toolCalls
                )
                if let data = try? JSONEncoder().encode(toolCallChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }

                let finishChunk = ChatCompletionChunk(
                    id: completionId,
                    model: model,
                    choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "tool_calls")]
                )
                if let data = try? JSONEncoder().encode(finishChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }
            } else {
                let stopChunk = ChatCompletionChunk.makeStopDelta(id: completionId, model: model)
                if let data = try? JSONEncoder().encode(stopChunk),
                   let jsonString = String(data: data, encoding: .utf8) {
                    continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
                }
            }

            continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
            continuation.finish()
        }

        return Response(
            status: .ok,
            headers: sseHeaders(),
            body: .init(asyncSequence: responseStream)
        )
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

    private func errorResponse(
        status: HTTPResponse.Status,
        type: String,
        message: String
    ) -> Response {
        let body: [String: [String: String]] = [
            "error": [
                "message": "\(message)",
                "type": type,
            ],
        ]

        let data = (try? JSONEncoder().encode(body)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    private func anyToAnyCodable(_ value: Any) -> AnyCodable {
        switch value {
        case let string as String:
            AnyCodable(.string(string))
        case let int as Int:
            AnyCodable(.int(int))
        case let double as Double:
            AnyCodable(.double(double))
        case let bool as Bool:
            AnyCodable(.bool(bool))
        case let array as [Any]:
            AnyCodable(.array(array.map { anyToAnyCodable($0) }))
        case let dict as [String: Any]:
            AnyCodable(.dictionary(dict.compactMapValues { anyToAnyCodable($0) }))
        default:
            AnyCodable(.null)
        }
    }
}

private enum CompletionsHandlerError: Error {
    case timeout
}

private struct CollectedResponse: Sendable {
    let content: String
    let toolCalls: [ToolCall]
}

private final class ToolCallBuilder: @unchecked Sendable {
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