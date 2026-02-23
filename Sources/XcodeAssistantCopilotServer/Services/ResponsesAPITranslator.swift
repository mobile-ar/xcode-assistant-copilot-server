import Foundation

public struct ResponsesAPITranslator: Sendable {
    private let logger: LoggerProtocol

    public init(logger: LoggerProtocol) {
        self.logger = logger
    }

    public func translateRequest(from request: CopilotChatRequest) -> ResponsesAPIRequest {
        logger.debug("Translating CopilotChatRequest to ResponsesAPIRequest for model: \(request.model)")
        logger.debug("Input messages count: \(request.messages.count), tools count: \(request.tools?.count ?? 0), stream: \(request.stream)")
        var instructions: String?
        var inputItems: [ResponsesInputItem] = []

        for message in request.messages {
            guard let role = message.role else { continue }

            switch role {
            case .system, .developer:
                let text = (try? message.extractContentText()) ?? ""
                guard !text.isEmpty else { continue }
                if let existing = instructions {
                    instructions = existing + "\n" + text
                } else {
                    instructions = text
                }

            case .user:
                let text = (try? message.extractContentText()) ?? ""
                inputItems.append(.message(ResponsesMessage(role: "user", content: text)))

            case .assistant:
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    let text = (try? message.extractContentText()) ?? ""
                    if !text.isEmpty {
                        inputItems.append(.message(ResponsesMessage(role: "assistant", content: text)))
                    }
                    for tc in toolCalls {
                        let callId = tc.id ?? UUID().uuidString
                        inputItems.append(.functionCall(ResponsesFunctionCall(
                            id: callId,
                            callId: callId,
                            name: tc.function.name,
                            arguments: tc.function.arguments
                        )))
                    }
                } else {
                    let text = (try? message.extractContentText()) ?? ""
                    inputItems.append(.message(ResponsesMessage(role: "assistant", content: text)))
                }

            case .tool:
                if let callId = message.toolCallId {
                    let text = (try? message.extractContentText()) ?? ""
                    inputItems.append(.functionCallOutput(ResponsesFunctionCallOutput(
                        callId: callId,
                        output: text
                    )))
                }
            }
        }

        let responsesTools = request.tools?.map { tool in
            ResponsesAPITool(
                name: tool.function.name,
                description: tool.function.description,
                parameters: tool.function.parameters
            )
        }

        let reasoning = request.reasoningEffort.map { ResponsesReasoning(effort: $0.rawValue) }

        let result = ResponsesAPIRequest(
            model: request.model,
            input: inputItems,
            stream: request.stream,
            instructions: instructions,
            tools: responsesTools?.isEmpty == true ? nil : responsesTools,
            toolChoice: request.toolChoice,
            reasoning: reasoning
        )
        logger.debug("Translated request: model=\(result.model), input items=\(result.input.count), has instructions=\(result.instructions != nil), tools=\(result.tools?.count ?? 0), reasoning=\(result.reasoning?.effort ?? "nil"), stream=\(result.stream)")
        if let encoded = try? JSONEncoder().encode(result),
           let json = String(data: encoded, encoding: .utf8) {
            logger.debug("Responses API request body: \(json)")
        }
        return result
    }

    public func adaptStream(
        events: AsyncThrowingStream<SSEEvent, Error>,
        completionId: String,
        model: String
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        logger.debug("adaptStream started for completionId=\(completionId), model=\(model)")
        return AsyncThrowingStream { continuation in
            let task = Task {
                let encoder = JSONEncoder()
                var toolCallIndex = 0
                var hasToolCalls = false
                var hasEmittedContentDeltas = false
                var emittedRole = false
                var eventCount = 0
                var emittedChunkCount = 0

                do {
                    for try await event in events {
                        eventCount += 1
                        if Task.isCancelled {
                            logger.debug("adaptStream: task cancelled after \(eventCount) events")
                            break
                        }
                        if event.isDone {
                            logger.debug("adaptStream: received [DONE] signal after \(eventCount) events")
                            break
                        }

                        let dataPreview = event.data.prefix(200)
                        // DEBUG: logger.debug("adaptStream: raw event #\(eventCount) — type=\(event.event ?? "nil"), data=\(dataPreview)") // DEBUG: All raw event = too much console output

                        let eventType: ResponsesEventType
                        if let eventTypeName = event.event,
                           let parsed = ResponsesEventType(rawValue: eventTypeName) {
                            eventType = parsed
                        } else if let fallback = ResponsesEventType.fromDataType(event.data) {
                            logger.debug("adaptStream: resolved event type from data payload: \(fallback.rawValue)")
                            eventType = fallback
                        } else {
                            logger.debug("adaptStream: skipping event with unrecognized type: \(event.event ?? "nil"), data preview: \(dataPreview)")
                            continue
                        }

                        switch eventType {
                        case .outputTextDelta:
                            let delta: ResponsesTextDeltaEvent
                            do {
                                delta = try event.decodeData(ResponsesTextDeltaEvent.self)
                            } catch {
                                logger.warn("adaptStream: failed to decode outputTextDelta: \(error), data: \(dataPreview)")
                                continue
                            }
                            // DEBUG: logger.debug("adaptStream: outputTextDelta — delta length=\(delta.delta.count), preview=\(delta.delta.prefix(100))") // DEBUG: All the output delta = too much console output
                            hasEmittedContentDeltas = true
                            if !emittedRole {
                                emitRoleDelta(
                                    continuation: continuation,
                                    encoder: encoder,
                                    completionId: completionId,
                                    model: model,
                                    emittedChunkCount: &emittedChunkCount
                                )
                                emittedRole = true
                            }
                            let chunk = ChatCompletionChunk.makeContentDelta(
                                id: completionId,
                                model: model,
                                content: delta.delta
                            )
                            emitChunk(chunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)

                        case .outputItemAdded:
                            let added: ResponsesOutputItemAddedEvent
                            do {
                                added = try event.decodeData(ResponsesOutputItemAddedEvent.self)
                            } catch {
                                logger.warn("adaptStream: failed to decode outputItemAdded: \(error), data: \(dataPreview)")
                                continue
                            }
                            logger.debug("adaptStream: outputItemAdded — item type=\(added.item.type), id=\(added.item.id ?? "nil"), name=\(added.item.name ?? "nil")")
                            guard added.item.type == "function_call" else {
                                logger.debug("adaptStream: skipping non-function_call output item of type: \(added.item.type)")
                                continue
                            }
                            if !emittedRole {
                                emitRoleDelta(
                                    continuation: continuation,
                                    encoder: encoder,
                                    completionId: completionId,
                                    model: model,
                                    emittedChunkCount: &emittedChunkCount
                                )
                                emittedRole = true
                            }
                            hasToolCalls = true
                            let tc = ToolCall(
                                index: toolCallIndex,
                                id: added.item.callId ?? added.item.id,
                                type: "function",
                                function: ToolCallFunction(
                                    name: added.item.name ?? "",
                                    arguments: ""
                                )
                            )
                            let chunk = ChatCompletionChunk.makeToolCallDelta(
                                id: completionId,
                                model: model,
                                toolCalls: [tc]
                            )
                            emitChunk(chunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)
                            toolCallIndex += 1

                        case .functionCallArgumentsDelta:
                            let delta: ResponsesFunctionCallArgsDeltaEvent
                            do {
                                delta = try event.decodeData(ResponsesFunctionCallArgsDeltaEvent.self)
                            } catch {
                                logger.warn("adaptStream: failed to decode functionCallArgumentsDelta: \(error), data: \(dataPreview)")
                                continue
                            }
                            logger.debug("adaptStream: functionCallArgumentsDelta — delta=\(delta.delta.prefix(100)), callId=\(delta.callId ?? "nil")")
                            let currentIndex = max(toolCallIndex - 1, 0)
                            let tc = ToolCall(
                                index: currentIndex,
                                function: ToolCallFunction(
                                    name: "",
                                    arguments: delta.delta
                                )
                            )
                            let chunk = ChatCompletionChunk.makeToolCallDelta(
                                id: completionId,
                                model: model,
                                toolCalls: [tc]
                            )
                            emitChunk(chunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)

                        case .responseCompleted:
                            logger.info("adaptStream: responseCompleted — hasToolCalls=\(hasToolCalls), emittedChunks=\(emittedChunkCount), total raw events=\(eventCount)")
                            logger.debug("adaptStream: responseCompleted full data: \(event.data)")
                            if !emittedRole {
                                emitRoleDelta(
                                    continuation: continuation,
                                    encoder: encoder,
                                    completionId: completionId,
                                    model: model,
                                    emittedChunkCount: &emittedChunkCount
                                )
                                emittedRole = true
                            }

                            do {
                                let completed = try event.decodeData(ResponsesCompletedEvent.self)
                                logger.debug("adaptStream: responseCompleted decoded — status=\(completed.response.status), output items=\(completed.response.output?.count ?? 0)")
                                let extractedContent = extractCompletedContent(from: completed)

                                if !extractedContent.text.isEmpty && !hasEmittedContentDeltas && !hasToolCalls {
                                    logger.info("adaptStream: emitting extracted text content (length=\(extractedContent.text.count)) from completed response")
                                    let contentChunk = ChatCompletionChunk.makeContentDelta(
                                        id: completionId,
                                        model: model,
                                        content: extractedContent.text
                                    )
                                    emitChunk(contentChunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)
                                }

                                if !hasToolCalls {
                                    for tc in extractedContent.toolCalls {
                                        hasToolCalls = true
                                        logger.info("adaptStream: emitting extracted tool call '\(tc.name)' (callId=\(tc.callId)) from completed response")
                                        let headerTC = ToolCall(
                                            index: toolCallIndex,
                                            id: tc.callId,
                                            type: "function",
                                            function: ToolCallFunction(name: tc.name, arguments: "")
                                        )
                                        let headerChunk = ChatCompletionChunk.makeToolCallDelta(
                                            id: completionId,
                                            model: model,
                                            toolCalls: [headerTC]
                                        )
                                        emitChunk(headerChunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)

                                        let argsTC = ToolCall(
                                            index: toolCallIndex,
                                            function: ToolCallFunction(name: "", arguments: tc.arguments)
                                        )
                                        let argsChunk = ChatCompletionChunk.makeToolCallDelta(
                                            id: completionId,
                                            model: model,
                                            toolCalls: [argsTC]
                                        )
                                        emitChunk(argsChunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)
                                        toolCallIndex += 1
                                    }
                                }
                            } catch {
                                logger.error("adaptStream: failed to decode responseCompleted event: \(error)")
                                logger.error("adaptStream: responseCompleted raw data that failed decoding: \(event.data)")
                            }

                            let finishReason = hasToolCalls ? "tool_calls" : "stop"
                            let chunk = ChatCompletionChunk(
                                id: completionId,
                                model: model,
                                choices: [ChunkChoice(delta: ChunkDelta(), finishReason: finishReason)]
                            )
                            emitChunk(chunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)

                        case .responseFailed, .responseIncomplete:
                            logger.warn("adaptStream: \(eventType.rawValue) received — data=\(dataPreview)")
                            if !emittedRole {
                                emitRoleDelta(
                                    continuation: continuation,
                                    encoder: encoder,
                                    completionId: completionId,
                                    model: model,
                                    emittedChunkCount: &emittedChunkCount
                                )
                                emittedRole = true
                            }
                            let chunk = ChatCompletionChunk(
                                id: completionId,
                                model: model,
                                choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "stop")]
                            )
                            emitChunk(chunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)

                        case .responseCreated,
                             .responseInProgress,
                             .outputItemDone,
                             .contentPartAdded,
                             .contentPartDone,
                             .outputTextDone,
                             .functionCallArgumentsDone,
                             .reasoningDelta,
                             .reasoningDone,
                             .reasoningSummaryDelta,
                             .reasoningSummaryDone,
                             .reasoningSummaryTextDelta,
                             .reasoningSummaryTextDone:
                            logger.debug("adaptStream: passthrough event \(eventType.rawValue) (no action)")
                            continue
                        }
                    }
                } catch {
                    logger.error("adaptStream: stream error after \(eventCount) events — \(error)")
                    continuation.finish(throwing: error)
                    return
                }

                logger.debug("adaptStream: stream finished — total raw events=\(eventCount), emitted chunks=\(emittedChunkCount)")
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func extractCompletedContent(from completed: ResponsesCompletedEvent) -> ExtractedCompletedContent {
        var textParts: [String] = []
        var toolCalls: [ExtractedToolCall] = []

        guard let output = completed.response.output else {
            logger.debug("extractCompletedContent: no output items in completed response")
            return ExtractedCompletedContent(text: "", toolCalls: [])
        }

        for item in output {
            logger.debug("extractCompletedContent: processing output item type=\(item.type), id=\(item.id ?? "nil")")
            switch item.type {
            case "message":
                if let contentParts = item.content {
                    for part in contentParts {
                        if let text = part.text, !text.isEmpty {
                            logger.debug("extractCompletedContent: found text part (length=\(text.count))")
                            textParts.append(text)
                        }
                    }
                }
            case "function_call":
                let callId = item.callId ?? item.id ?? UUID().uuidString
                let name = item.name ?? ""
                let arguments = item.arguments ?? "{}"
                logger.debug("extractCompletedContent: found function_call — name=\(name), callId=\(callId)")
                toolCalls.append(ExtractedToolCall(callId: callId, name: name, arguments: arguments))
            default:
                logger.debug("extractCompletedContent: skipping unknown output item type: \(item.type)")
            }
        }

        return ExtractedCompletedContent(text: textParts.joined(), toolCalls: toolCalls)
    }

    private func emitRoleDelta(
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
        encoder: JSONEncoder,
        completionId: String,
        model: String,
        emittedChunkCount: inout Int
    ) {
        let roleChunk = ChatCompletionChunk.makeRoleDelta(id: completionId, model: model)
        emitChunk(roleChunk, continuation: continuation, encoder: encoder, emittedChunkCount: &emittedChunkCount)
    }

    private func emitChunk(
        _ chunk: ChatCompletionChunk,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
        encoder: JSONEncoder,
        emittedChunkCount: inout Int
    ) {
        guard let data = try? encoder.encode(chunk),
              let json = String(data: data, encoding: .utf8) else {
            logger.warn("adaptStream: failed to encode ChatCompletionChunk")
            return
        }
        emittedChunkCount += 1
        continuation.yield(SSEEvent(data: json))
    }
}
