import Testing
import Foundation
@testable import XcodeAssistantCopilotServer

@Test func translateRequestConvertsUserMessage() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hello world"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.model == "gpt-5.1-codex")
    #expect(result.stream == true)
    #expect(result.input.count == 1)
    #expect(result.instructions == nil)

    let encoded = try JSONEncoder().encode(result.input[0])
    let dict = try JSONDecoder().decode([String: String].self, from: encoded)
    #expect(dict["role"] == "user")
    #expect(dict["content"] == "Hello world")
}

@Test func translateRequestExtractsSystemMessageAsInstructions() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("You are helpful")),
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.instructions == "You are helpful")
    #expect(result.input.count == 1)
}

@Test func translateRequestConcatenatesMultipleSystemMessages() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("Rule 1")),
            ChatCompletionMessage(role: .system, content: .text("Rule 2")),
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.instructions == "Rule 1\nRule 2")
}

@Test func translateRequestConvertsDeveloperMessageAsInstructions() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .developer, content: .text("Developer instructions")),
            ChatCompletionMessage(role: .user, content: .text("Go"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.instructions == "Developer instructions")
    #expect(result.input.count == 1)
}

@Test func translateRequestConvertsAssistantMessage() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi")),
            ChatCompletionMessage(role: .assistant, content: .text("Hello!"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 2)

    let encoded = try JSONEncoder().encode(result.input[1])
    let dict = try JSONDecoder().decode([String: String].self, from: encoded)
    #expect(dict["role"] == "assistant")
    #expect(dict["content"] == "Hello!")
}

@Test func translateRequestConvertsAssistantToolCalls() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let toolCall = ToolCall(
        id: "call_123",
        type: "function",
        function: ToolCallFunction(name: "get_weather", arguments: "{\"city\":\"NYC\"}")
    )
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Weather?")),
            ChatCompletionMessage(role: .assistant, content: MessageContent.none, toolCalls: [toolCall])
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 2)

    let encoded = try JSONEncoder().encode(result.input[1])
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(json?["type"] as? String == "function_call")
    #expect(json?["call_id"] as? String == "call_123")
    #expect(json?["name"] as? String == "get_weather")
    #expect(json?["arguments"] as? String == "{\"city\":\"NYC\"}")
}

@Test func translateRequestConvertsAssistantWithContentAndToolCalls() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let toolCall = ToolCall(
        id: "call_456",
        type: "function",
        function: ToolCallFunction(name: "search", arguments: "{}")
    )
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(
                role: .assistant,
                content: .text("Let me search"),
                toolCalls: [toolCall]
            )
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 2)

    let messageEncoded = try JSONEncoder().encode(result.input[0])
    let messageDict = try JSONDecoder().decode([String: String].self, from: messageEncoded)
    #expect(messageDict["role"] == "assistant")
    #expect(messageDict["content"] == "Let me search")

    let callEncoded = try JSONEncoder().encode(result.input[1])
    let callDict = try JSONSerialization.jsonObject(with: callEncoded) as? [String: Any]
    #expect(callDict?["type"] as? String == "function_call")
    #expect(callDict?["name"] as? String == "search")
}

@Test func translateRequestConvertsToolMessage() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(
                role: .tool,
                content: .text("Sunny, 72°F"),
                toolCallId: "call_123"
            )
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 1)

    let encoded = try JSONEncoder().encode(result.input[0])
    let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call_output")
    #expect(dict?["call_id"] as? String == "call_123")
    #expect(dict?["output"] as? String == "Sunny, 72°F")
}

@Test func translateRequestConvertsTools() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let tool = Tool(
        type: "function",
        function: ToolFunction(
            name: "get_weather",
            description: "Get the weather",
            parameters: [
                "type": AnyCodable(.string("object")),
                "properties": AnyCodable(.dictionary([
                    "city": AnyCodable(.dictionary([
                        "type": AnyCodable(.string("string"))
                    ]))
                ]))
            ]
        )
    )

    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [ChatCompletionMessage(role: .user, content: .text("Weather"))],
        tools: [tool]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.tools?.count == 1)
    let rTool = result.tools![0]

    let encoded = try JSONEncoder().encode(rTool)
    let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(dict?["type"] as? String == "function")
    #expect(dict?["name"] as? String == "get_weather")
    #expect(dict?["description"] as? String == "Get the weather")
    #expect(dict?["parameters"] != nil)
}

@Test func translateRequestConvertsReasoningEffort() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))],
        reasoningEffort: .high
    )

    let result = translator.translateRequest(from: request)

    #expect(result.reasoning?.effort == "high")
}

@Test func translateRequestOmitsReasoningWhenNil() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.reasoning == nil)
}

@Test func translateRequestOmitsToolsWhenEmpty() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))],
        tools: []
    )

    let result = translator.translateRequest(from: request)

    #expect(result.tools == nil)
}

@Test func translateRequestSkipsMessagesWithNoRole() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(content: .text("No role")),
            ChatCompletionMessage(role: .user, content: .text("Has role"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 1)
}

@Test func translateRequestPassesToolChoice() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))],
        toolChoice: AnyCodable(.string("auto"))
    )

    let result = translator.translateRequest(from: request)

    let encoded = try JSONEncoder().encode(result)
    let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(dict?["tool_choice"] as? String == "auto")
}

@Test func translateRequestHandlesEmptyMessages() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: []
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.isEmpty)
    #expect(result.instructions == nil)
}

@Test func translateRequestSkipsEmptySystemContent() {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("")),
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.instructions == nil)
}

@Test func translateRequestFullConversationRoundTrip() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let toolCall = ToolCall(
        id: "call_abc",
        type: "function",
        function: ToolCallFunction(name: "read_file", arguments: "{\"path\":\"/tmp/test\"}")
    )
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("You are a coder")),
            ChatCompletionMessage(role: .user, content: .text("Read the file")),
            ChatCompletionMessage(role: .assistant, content: MessageContent.none, toolCalls: [toolCall]),
            ChatCompletionMessage(role: .tool, content: .text("file contents here"), toolCallId: "call_abc"),
            ChatCompletionMessage(role: .assistant, content: .text("Here is the file"))
        ],
        tools: [Tool(type: "function", function: ToolFunction(name: "read_file", description: "Read a file"))],
        reasoningEffort: .xhigh,
        stream: true
    )

    let result = translator.translateRequest(from: request)

    #expect(result.model == "gpt-5.1-codex")
    #expect(result.instructions == "You are a coder")
    #expect(result.stream == true)
    #expect(result.reasoning?.effort == "xhigh")
    #expect(result.tools?.count == 1)
    #expect(result.input.count == 4)

    let encoded = try JSONEncoder().encode(result)
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(json?["model"] as? String == "gpt-5.1-codex")
    #expect(json?["instructions"] as? String == "You are a coder")
}

@Test func translateRequestEncodesValidJSON() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("Be helpful")),
            ChatCompletionMessage(role: .user, content: .text("Hello"))
        ],
        reasoningEffort: .high
    )

    let result = translator.translateRequest(from: request)

    let data = try JSONEncoder().encode(result)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["model"] as? String == "gpt-5.1-codex")
    #expect(json?["stream"] as? Bool == true)
    #expect(json?["instructions"] as? String == "Be helpful")

    let reasoning = json?["reasoning"] as? [String: Any]
    #expect(reasoning?["effort"] as? String == "high")

    let input = json?["input"] as? [[String: Any]]
    #expect(input?.count == 1)
    #expect(input?[0]["role"] as? String == "user")
    #expect(input?[0]["content"] as? String == "Hello")
}

@Test func adaptStreamConvertsTextDelta() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hello \"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"world\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    #expect(chunks.count >= 3)

    let roleChunk = chunks[0]
    #expect(roleChunk.choices.first?.delta?.role == .assistant)
    #expect(roleChunk.id == "chatcmpl-test")
    #expect(roleChunk.model == "gpt-5.1-codex")

    let contentChunk1 = chunks[1]
    #expect(contentChunk1.choices.first?.delta?.content == "Hello ")

    let contentChunk2 = chunks[2]
    #expect(contentChunk2.choices.first?.delta?.content == "world")

    let finishChunk = chunks.last!
    #expect(finishChunk.choices.first?.finishReason == "stop")
}

@Test func adaptStreamConvertsToolCalls() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_123\",\"name\":\"get_weather\",\"status\":\"in_progress\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"{\\\"city\\\"\",\"call_id\":\"call_123\",\"output_index\":0}",
            event: "response.function_call_arguments.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\":\\\"NYC\\\"}\",\"call_id\":\"call_123\",\"output_index\":0}",
            event: "response.function_call_arguments.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    #expect(chunks.count >= 3)

    let roleChunk = chunks[0]
    #expect(roleChunk.choices.first?.delta?.role == .assistant)

    let toolStartChunk = chunks[1]
    let startToolCalls = toolStartChunk.choices.first?.delta?.toolCalls
    #expect(startToolCalls?.count == 1)
    #expect(startToolCalls?[0].id == "call_123")
    #expect(startToolCalls?[0].function.name == "get_weather")
    #expect(startToolCalls?[0].index == 0)

    let argDeltaChunk = chunks[2]
    let argToolCalls = argDeltaChunk.choices.first?.delta?.toolCalls
    #expect(argToolCalls?[0].index == 0)
    #expect(argToolCalls?[0].function.arguments == "{\"city\"")

    let finishChunk = chunks.last!
    #expect(finishChunk.choices.first?.finishReason == "tool_calls")
}

@Test func adaptStreamEmitsDoneEvent() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hi\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var gotDone = false
    for try await event in adapted {
        if event.isDone {
            gotDone = true
        }
    }

    #expect(gotDone)
}

@Test func adaptStreamSkipsUnknownEventTypes() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"id\":\"resp_1\"}",
            event: "response.created"
        ))
        continuation.yield(SSEEvent(
            data: "{}",
            event: "response.content_part.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hello\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"text\":\"Hello\"}",
            event: "response.output_text.done"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Hello")
    #expect(chunks[2].choices.first?.finishReason == "stop")
}

@Test func adaptStreamHandlesEmptyStream() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var eventCount = 0
    for try await event in adapted {
        if event.isDone { break }
        eventCount += 1
    }

    #expect(eventCount == 0)
}

@Test func adaptStreamHandlesResponseFailed() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"partial\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"failed\"}}",
            event: "response.failed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    let finishChunk = chunks.last
    #expect(finishChunk?.choices.first?.finishReason == "stop")
}

@Test func adaptStreamHandlesResponseIncomplete() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{}",
            event: "response.incomplete"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    #expect(chunks.count >= 1)
    let finishChunk = chunks.last
    #expect(finishChunk?.choices.first?.finishReason == "stop")
}

@Test func adaptStreamPropagatesErrors() async {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    struct TestStreamError: Error {}

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"start\"}",
            event: "response.output_text.delta"
        ))
        continuation.finish(throwing: TestStreamError())
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var caughtError = false
    do {
        for try await _ in adapted {
            // consume
        }
    } catch {
        caughtError = true
    }

    #expect(caughtError)
}

@Test func adaptStreamHandlesMultipleToolCalls() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"tool_a\",\"status\":\"in_progress\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"{}\",\"call_id\":\"call_1\",\"output_index\":0}",
            event: "response.function_call_arguments.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"arguments\":\"{}\",\"call_id\":\"call_1\",\"output_index\":0}",
            event: "response.function_call_arguments.done"
        ))
        continuation.yield(SSEEvent(
            data: "{\"output_index\":1,\"item\":{\"type\":\"function_call\",\"id\":\"fc_2\",\"call_id\":\"call_2\",\"name\":\"tool_b\",\"status\":\"in_progress\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"{\\\"x\\\":1}\",\"call_id\":\"call_2\",\"output_index\":1}",
            event: "response.function_call_arguments.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    let toolStartChunks = chunks.filter { chunk in
        chunk.choices.first?.delta?.toolCalls?.first?.id != nil
    }
    #expect(toolStartChunks.count == 2)
    #expect(toolStartChunks[0].choices.first?.delta?.toolCalls?[0].index == 0)
    #expect(toolStartChunks[0].choices.first?.delta?.toolCalls?[0].function.name == "tool_a")
    #expect(toolStartChunks[1].choices.first?.delta?.toolCalls?[0].index == 1)
    #expect(toolStartChunks[1].choices.first?.delta?.toolCalls?[0].function.name == "tool_b")

    let finishChunk = chunks.last!
    #expect(finishChunk.choices.first?.finishReason == "tool_calls")
}

@Test func adaptStreamHandlesNonFunctionCallOutputItem() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"output_index\":0,\"item\":{\"type\":\"message\",\"role\":\"assistant\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hello\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    let toolChunks = chunks.filter { chunk in
        chunk.choices.first?.delta?.toolCalls != nil
    }
    #expect(toolChunks.isEmpty)
    #expect(chunks.last?.choices.first?.finishReason == "stop")
}

@Test func adaptStreamSetsCorrectModelAndId() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hi\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-custom-id",
        model: "gpt-5.1-codex-max"
    )

    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            #expect(chunk.id == "chatcmpl-custom-id")
            #expect(chunk.model == "gpt-5.1-codex-max")
        }
    }
}

@Test func adaptStreamHandlesIncomingDoneSignal() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hi\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(data: "[DONE]"))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var gotDone = false
    for try await event in adapted {
        if event.isDone {
            gotDone = true
        }
    }

    #expect(gotDone)
}

@Test func adaptStreamIgnoresEventsWithNoEventType() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(data: "{\"some\":\"data\"}"))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"actual content\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.1-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        if let chunk = try? event.decodeData(ChatCompletionChunk.self) {
            chunks.append(chunk)
        }
    }

    #expect(chunks.count == 3)
    #expect(chunks[1].choices.first?.delta?.content == "actual content")
}

@Test func translateRequestMultipleToolCallsInSingleAssistantMessage() throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())
    let tc1 = ToolCall(
        id: "call_1",
        type: "function",
        function: ToolCallFunction(name: "tool_a", arguments: "{}")
    )
    let tc2 = ToolCall(
        id: "call_2",
        type: "function",
        function: ToolCallFunction(name: "tool_b", arguments: "{\"x\":1}")
    )

    let request = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .assistant, content: MessageContent.none, toolCalls: [tc1, tc2])
        ]
    )

    let result = translator.translateRequest(from: request)

    #expect(result.input.count == 2)

    let first = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(result.input[0])
    ) as? [String: Any]
    #expect(first?["name"] as? String == "tool_a")
    #expect(first?["call_id"] as? String == "call_1")

    let second = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(result.input[1])
    ) as? [String: Any]
    #expect(second?["name"] as? String == "tool_b")
    #expect(second?["call_id"] as? String == "call_2")
}

@Test func adaptStreamExtractsTextFromCompletedWhenNoDeltasStreamed() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Hello from completed response"}]}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Hello from completed response")
    #expect(chunks[2].choices.first?.finishReason == "stop")
}

@Test func adaptStreamExtractsToolCallsFromCompletedWhenNoDeltasStreamed() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_abc","name":"get_weather","arguments":"{\\"city\\":\\"NYC\\"}"}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 4)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)

    let headerTC = chunks[1].choices.first?.delta?.toolCalls?.first
    #expect(headerTC?.id == "call_abc")
    #expect(headerTC?.function.name == "get_weather")
    #expect(headerTC?.index == 0)

    let argsTC = chunks[2].choices.first?.delta?.toolCalls?.first
    #expect(argsTC?.function.arguments == "{\"city\":\"NYC\"}")
    #expect(argsTC?.index == 0)

    #expect(chunks[3].choices.first?.finishReason == "tool_calls")
}

@Test func adaptStreamDoesNotDoubleEmitTextWhenDeltasAlreadyStreamed() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Hello world"}]}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hello \"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"world\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var contentPieces: [String] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        if let content = chunk.choices.first?.delta?.content {
            contentPieces.append(content)
        }
    }

    #expect(contentPieces == ["Hello ", "world"])
}

@Test func adaptStreamDoesNotDoubleEmitToolCallsWhenAlreadyStreamed() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_123","name":"get_weather","arguments":"{}"}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_123\",\"name\":\"get_weather\",\"status\":\"in_progress\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"{}\",\"call_id\":\"call_123\",\"output_index\":0}",
            event: "response.function_call_arguments.delta"
        ))
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var toolCallChunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        if chunk.choices.first?.delta?.toolCalls != nil {
            toolCallChunks.append(chunk)
        }
    }

    #expect(toolCallChunks.count == 2)
    #expect(toolCallChunks[0].choices.first?.delta?.toolCalls?.first?.function.name == "get_weather")
    #expect(toolCallChunks[1].choices.first?.delta?.toolCalls?.first?.function.arguments == "{}")
}

@Test func adaptStreamExtractsMultipleToolCallsFromCompleted() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"tool_a","arguments":"{}"},{"type":"function_call","id":"fc_2","call_id":"call_2","name":"tool_b","arguments":"{\\"x\\":1}"}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var toolCallChunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        if chunk.choices.first?.delta?.toolCalls != nil {
            toolCallChunks.append(chunk)
        }
    }

    #expect(toolCallChunks.count == 4)

    #expect(toolCallChunks[0].choices.first?.delta?.toolCalls?.first?.id == "call_1")
    #expect(toolCallChunks[0].choices.first?.delta?.toolCalls?.first?.function.name == "tool_a")
    #expect(toolCallChunks[0].choices.first?.delta?.toolCalls?.first?.index == 0)

    #expect(toolCallChunks[1].choices.first?.delta?.toolCalls?.first?.function.arguments == "{}")
    #expect(toolCallChunks[1].choices.first?.delta?.toolCalls?.first?.index == 0)

    #expect(toolCallChunks[2].choices.first?.delta?.toolCalls?.first?.id == "call_2")
    #expect(toolCallChunks[2].choices.first?.delta?.toolCalls?.first?.function.name == "tool_b")
    #expect(toolCallChunks[2].choices.first?.delta?.toolCalls?.first?.index == 1)

    #expect(toolCallChunks[3].choices.first?.delta?.toolCalls?.first?.function.arguments == "{\"x\":1}")
    #expect(toolCallChunks[3].choices.first?.delta?.toolCalls?.first?.index == 1)
}

@Test func adaptStreamExtractsTextAndToolCallsFromCompleted() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Let me check"}]},{"type":"function_call","id":"fc_1","call_id":"call_1","name":"search","arguments":"{\\"q\\":\\"test\\"}"}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 5)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Let me check")
    #expect(chunks[2].choices.first?.delta?.toolCalls?.first?.function.name == "search")
    #expect(chunks[3].choices.first?.delta?.toolCalls?.first?.function.arguments == "{\"q\":\"test\"}")
    #expect(chunks[4].choices.first?.finishReason == "tool_calls")
}

@Test func adaptStreamHandlesCompletedWithEmptyOutput() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"response":{"id":"resp_1","status":"completed","output":[]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-test",
        model: "gpt-5.2-codex"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 2)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.finishReason == "stop")
}

@Test func adaptStreamResolvesEventTypeFromDataPayloadWhenSSEEventFieldMissing() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello from fallback\"}",
            event: nil
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: nil
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-fallback",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Hello from fallback")
    #expect(chunks[2].choices.first?.finishReason == "stop")
}

@Test func adaptStreamResolvesCompletedFromDataPayloadWhenSSEEventFieldMissing() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let completedData = """
    {"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Extracted from completed"}]}]}}
    """

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: completedData,
            event: nil
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-fallback2",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Extracted from completed")
    #expect(chunks[2].choices.first?.finishReason == "stop")
}

@Test func adaptStreamMixesSSEEventFieldAndDataPayloadFallback() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.output_text.delta\",\"delta\":\"Part1\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.output_text.delta\",\"delta\":\" Part2\"}",
            event: nil
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: nil
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-mix",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 4)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "Part1")
    #expect(chunks[2].choices.first?.delta?.content == " Part2")
    #expect(chunks[3].choices.first?.finishReason == "stop")
}

@Test func adaptStreamSkipsReasoningEventsAndStillEmitsContent() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_1\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"thinking...\"}",
            event: "response.reasoning.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"text\":\"done thinking\"}",
            event: "response.reasoning.done"
        ))
        continuation.yield(SSEEvent(
            data: "{\"output_index\":1,\"item\":{\"type\":\"message\",\"id\":\"msg_1\"}}",
            event: "response.output_item.added"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"The answer is 42\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-reason",
        model: "o3"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)
    #expect(chunks[1].choices.first?.delta?.content == "The answer is 42")
    #expect(chunks[2].choices.first?.finishReason == "stop")
}

@Test func adaptStreamHandlesInProgressEventWithoutError() async throws {
    let logger = MockLogger()
    let translator = ResponsesAPITranslator(logger: logger)

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"in_progress\"}}",
            event: "response.in_progress"
        ))
        continuation.yield(SSEEvent(
            data: "{\"delta\":\"Hi\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-inprogress",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[1].choices.first?.delta?.content == "Hi")
    #expect(logger.errorMessages.isEmpty)
}

@Test func adaptStreamFallbackResolvesToolCallsFromDataPayload() async throws {
    let translator = ResponsesAPITranslator(logger: MockLogger())

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"get_weather\"}}",
            event: nil
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.function_call_arguments.delta\",\"delta\":\"{\\\"city\\\":\",\"call_id\":\"call_1\",\"output_index\":0}",
            event: nil
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.function_call_arguments.delta\",\"delta\":\"\\\"NYC\\\"}\",\"call_id\":\"call_1\",\"output_index\":0}",
            event: nil
        ))
        continuation.yield(SSEEvent(
            data: "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: nil
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-tc-fallback",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    #expect(chunks.count >= 4)
    #expect(chunks[0].choices.first?.delta?.role == .assistant)

    let headerTC = chunks[1].choices.first?.delta?.toolCalls?.first
    #expect(headerTC?.id == "call_1")
    #expect(headerTC?.function.name == "get_weather")

    let argsChunks = chunks.filter { chunk in
        chunk.choices.first?.delta?.toolCalls?.first?.function.arguments.isEmpty == false
    }
    let combinedArgs = argsChunks.compactMap { $0.choices.first?.delta?.toolCalls?.first?.function.arguments }.joined()
    #expect(combinedArgs == "{\"city\":\"NYC\"}")

    #expect(chunks.last?.choices.first?.finishReason == "tool_calls")
}

@Test func fromDataTypeReturnsCorrectEventType() {
    let outputTextDelta = ResponsesEventType.fromDataType("{\"type\":\"response.output_text.delta\",\"delta\":\"hi\"}")
    #expect(outputTextDelta == .outputTextDelta)

    let completed = ResponsesEventType.fromDataType("{\"type\":\"response.completed\",\"response\":{}}")
    #expect(completed == .responseCompleted)

    let inProgress = ResponsesEventType.fromDataType("{\"type\":\"response.in_progress\",\"response\":{}}")
    #expect(inProgress == .responseInProgress)

    let reasoning = ResponsesEventType.fromDataType("{\"type\":\"response.reasoning.delta\",\"delta\":\"think\"}")
    #expect(reasoning == .reasoningDelta)
}

@Test func fromDataTypeReturnsNilForInvalidData() {
    #expect(ResponsesEventType.fromDataType("not json") == nil)
    #expect(ResponsesEventType.fromDataType("{\"no_type\":\"field\"}") == nil)
    #expect(ResponsesEventType.fromDataType("{\"type\":\"unknown.event.type\"}") == nil)
    #expect(ResponsesEventType.fromDataType("") == nil)
}

@Test func adaptStreamLogsDecodingErrorsInsteadOfSilentlySkipping() async throws {
    let logger = MockLogger()
    let translator = ResponsesAPITranslator(logger: logger)

    let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.yield(SSEEvent(
            data: "{\"not_a_delta_field\":\"bad data\"}",
            event: "response.output_text.delta"
        ))
        continuation.yield(SSEEvent(
            data: "{\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}",
            event: "response.completed"
        ))
        continuation.finish()
    }

    let adapted = translator.adaptStream(
        events: events,
        completionId: "chatcmpl-err",
        model: "gpt-4.1"
    )

    var chunks: [ChatCompletionChunk] = []
    for try await event in adapted {
        if event.isDone { break }
        let chunk = try event.decodeData(ChatCompletionChunk.self)
        chunks.append(chunk)
    }

    let hasDecodingWarning = logger.warnMessages.contains { $0.contains("failed to decode outputTextDelta") }
    #expect(hasDecodingWarning)
}
