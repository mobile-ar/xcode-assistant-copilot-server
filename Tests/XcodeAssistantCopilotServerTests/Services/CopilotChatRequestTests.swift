import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func copilotChatRequestEncodesMinimalFields() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hello"))
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["model"] as? String == "gpt-4o")
    #expect(json["stream"] as? Bool == true)
    #expect(json["messages"] as? [[String: Any]] != nil)
    #expect(json["temperature"] == nil)
    #expect(json["top_p"] == nil)
    #expect(json["max_tokens"] == nil)
    #expect(json["stop"] == nil)
    #expect(json["tools"] == nil)
    #expect(json["tool_choice"] == nil)
    #expect(json["reasoning_effort"] == nil)
}

@Test func copilotChatRequestEncodesAllOptionalFields() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hello"))
        ],
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 1024,
        stop: .single("END"),
        tools: [
            Tool(
                type: "function",
                function: ToolFunction(
                    name: "get_weather",
                    description: "Get weather info",
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
        ],
        toolChoice: AnyCodable(.string("auto")),
        reasoningEffort: .high,
        stream: true
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["model"] as? String == "gpt-4o")
    #expect(json["stream"] as? Bool == true)
    #expect(json["temperature"] as? Double == 0.7)
    #expect(json["top_p"] as? Double == 0.9)
    #expect(json["max_tokens"] as? Int == 1024)
    #expect(json["stop"] as? String == "END")
    #expect(json["tool_choice"] as? String == "auto")
    #expect(json["reasoning_effort"] as? String == "high")

    let tools = json["tools"] as? [[String: Any]]
    #expect(tools?.count == 1)
    #expect(tools?.first?["type"] as? String == "function")

    let function = tools?.first?["function"] as? [String: Any]
    #expect(function?["name"] as? String == "get_weather")
    #expect(function?["description"] as? String == "Get weather info")
}

@Test func copilotChatRequestUsesSnakeCaseKeys() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        topP: 0.5,
        maxTokens: 100,
        reasoningEffort: .medium
    )

    let data = try JSONEncoder().encode(request)
    let jsonString = String(data: data, encoding: .utf8)!

    #expect(jsonString.contains("\"top_p\""))
    #expect(jsonString.contains("\"max_tokens\""))
    #expect(jsonString.contains("\"reasoning_effort\""))
    #expect(!jsonString.contains("\"topP\""))
    #expect(!jsonString.contains("\"maxTokens\""))
    #expect(!jsonString.contains("\"reasoningEffort\""))
}

@Test func copilotChatRequestOmitsEmptyTools() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        tools: []
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["tools"] == nil)
}

@Test func copilotChatRequestOmitsNilTools() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        tools: nil
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["tools"] == nil)
}

@Test func copilotChatRequestEncodesMultipleMessages() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("You are helpful.")),
            ChatCompletionMessage(role: .user, content: .text("Hello")),
            ChatCompletionMessage(role: .assistant, content: .text("Hi there!")),
            ChatCompletionMessage(role: .user, content: .text("How are you?")),
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = json["messages"] as? [[String: Any]]

    #expect(messages?.count == 4)
    #expect(messages?[0]["role"] as? String == "system")
    #expect(messages?[0]["content"] as? String == "You are helpful.")
    #expect(messages?[1]["role"] as? String == "user")
    #expect(messages?[2]["role"] as? String == "assistant")
    #expect(messages?[3]["role"] as? String == "user")
}

@Test func copilotChatRequestEncodesStreamFalse() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        stream: false
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["stream"] as? Bool == false)
}

@Test func copilotChatRequestEncodesStopSequenceMultiple() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        stop: .multiple(["END", "STOP", "DONE"])
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let stop = json["stop"] as? [String]
    #expect(stop == ["END", "STOP", "DONE"])
}

@Test func copilotChatRequestEncodesStopSequenceSingle() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        stop: .single("STOP")
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["stop"] as? String == "STOP")
}

@Test func copilotChatRequestEncodesToolChoiceObject() throws {
    let toolChoice = AnyCodable(.dictionary([
        "type": AnyCodable(.string("function")),
        "function": AnyCodable(.dictionary([
            "name": AnyCodable(.string("get_weather"))
        ]))
    ]))

    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        toolChoice: toolChoice
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let choice = json["tool_choice"] as? [String: Any]
    #expect(choice?["type"] as? String == "function")
    let function = choice?["function"] as? [String: Any]
    #expect(function?["name"] as? String == "get_weather")
}

@Test func copilotChatRequestEncodesAllReasoningEffortValues() throws {
    let efforts: [ReasoningEffort] = [.low, .medium, .high, .xhigh]
    let expectedStrings = ["low", "medium", "high", "xhigh"]

    for (effort, expectedString) in zip(efforts, expectedStrings) {
        let request = CopilotChatRequest(
            model: "gpt-4o",
            messages: [
                ChatCompletionMessage(role: .user, content: .text("Hi"))
            ],
            reasoningEffort: effort
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["reasoning_effort"] as? String == expectedString)
    }
}

@Test func copilotChatRequestEncodesMessageWithToolCalls() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(
                role: .assistant,
                content: MessageContent.none,
                toolCalls: [
                    ToolCall(
                        index: 0,
                        id: "call_123",
                        type: "function",
                        function: ToolCallFunction(
                            name: "get_weather",
                            arguments: "{\"city\":\"London\"}"
                        )
                    )
                ]
            ),
            ChatCompletionMessage(
                role: .tool,
                content: .text("Sunny, 22°C"),
                toolCallId: "call_123"
            ),
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = json["messages"] as? [[String: Any]]

    #expect(messages?.count == 2)

    let assistantMessage = messages?[0]
    #expect(assistantMessage?["role"] as? String == "assistant")
    let toolCalls = assistantMessage?["tool_calls"] as? [[String: Any]]
    #expect(toolCalls?.count == 1)
    #expect(toolCalls?[0]["id"] as? String == "call_123")
    #expect(toolCalls?[0]["type"] as? String == "function")
    let function = toolCalls?[0]["function"] as? [String: Any]
    #expect(function?["name"] as? String == "get_weather")
    #expect(function?["arguments"] as? String == "{\"city\":\"London\"}")

    let toolMessage = messages?[1]
    #expect(toolMessage?["role"] as? String == "tool")
    #expect(toolMessage?["content"] as? String == "Sunny, 22°C")
    #expect(toolMessage?["tool_call_id"] as? String == "call_123")
}

@Test func copilotChatRequestEncodesMessageContentNone() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .assistant, content: MessageContent.none)
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = json["messages"] as? [[String: Any]]
    let firstMessage = messages?.first

    #expect(firstMessage?["content"] is NSNull)
}

@Test func copilotChatRequestEncodesMessageContentParts() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(
                role: .user,
                content: .parts([
                    ContentPart(type: "text", text: "Hello"),
                    ContentPart(type: "text", text: "World"),
                ])
            )
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = json["messages"] as? [[String: Any]]
    let content = messages?.first?["content"] as? [[String: Any]]

    #expect(content?.count == 2)
    #expect(content?[0]["type"] as? String == "text")
    #expect(content?[0]["text"] as? String == "Hello")
    #expect(content?[1]["type"] as? String == "text")
    #expect(content?[1]["text"] as? String == "World")
}

@Test func copilotChatRequestEncodesMultipleTools() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        tools: [
            Tool(
                type: "function",
                function: ToolFunction(name: "tool_a", description: "First tool")
            ),
            Tool(
                type: "function",
                function: ToolFunction(name: "tool_b", description: nil, parameters: nil)
            ),
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let tools = json["tools"] as? [[String: Any]]

    #expect(tools?.count == 2)
    let funcA = tools?[0]["function"] as? [String: Any]
    #expect(funcA?["name"] as? String == "tool_a")
    #expect(funcA?["description"] as? String == "First tool")

    let funcB = tools?[1]["function"] as? [String: Any]
    #expect(funcB?["name"] as? String == "tool_b")
}

@Test func copilotChatRequestEncodesToolWithComplexParameters() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        tools: [
            Tool(
                type: "function",
                function: ToolFunction(
                    name: "search",
                    description: "Search for items",
                    parameters: [
                        "type": AnyCodable(.string("object")),
                        "required": AnyCodable(.array([AnyCodable(.string("query"))])),
                        "properties": AnyCodable(.dictionary([
                            "query": AnyCodable(.dictionary([
                                "type": AnyCodable(.string("string")),
                                "description": AnyCodable(.string("Search query"))
                            ])),
                            "limit": AnyCodable(.dictionary([
                                "type": AnyCodable(.string("integer")),
                                "default": AnyCodable(.int(10))
                            ]))
                        ]))
                    ]
                )
            )
        ]
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let tools = json["tools"] as? [[String: Any]]
    let function = tools?.first?["function"] as? [String: Any]
    let parameters = function?["parameters"] as? [String: Any]

    #expect(parameters?["type"] as? String == "object")
    let required = parameters?["required"] as? [String]
    #expect(required == ["query"])
    let properties = parameters?["properties"] as? [String: Any]
    let queryProp = properties?["query"] as? [String: Any]
    #expect(queryProp?["type"] as? String == "string")
    #expect(queryProp?["description"] as? String == "Search query")
    let limitProp = properties?["limit"] as? [String: Any]
    #expect(limitProp?["type"] as? String == "integer")
    #expect(limitProp?["default"] as? Int == 10)
}

@Test func copilotChatRequestDefaultStreamIsTrue() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ]
    )

    #expect(request.stream == true)

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["stream"] as? Bool == true)
}

@Test func copilotChatRequestEncodesTemperatureZero() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        temperature: 0.0
    )

    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["temperature"] as? Double == 0.0)
}

@Test func copilotChatRequestProducesValidJSON() throws {
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .system, content: .text("Be helpful.")),
            ChatCompletionMessage(role: .user, content: .text("What is 2+2?")),
        ],
        temperature: 0.5,
        topP: 0.95,
        maxTokens: 500,
        reasoningEffort: .high,
        stream: true
    )

    let data = try JSONEncoder().encode(request)
    let jsonString = String(data: data, encoding: .utf8)!

    #expect(!jsonString.isEmpty)

    let roundTripped = try JSONSerialization.jsonObject(with: data)
    #expect(roundTripped is [String: Any])
}

@Test func withReasoningEffortReturnsNewRequestWithUpdatedEffort() throws {
    let original = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hello"))
        ],
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 1024,
        reasoningEffort: .xhigh,
        stream: true
    )

    let updated = original.withReasoningEffort(.high)

    #expect(updated.reasoningEffort == .high)
    #expect(updated.model == original.model)
    #expect(updated.temperature == original.temperature)
    #expect(updated.topP == original.topP)
    #expect(updated.maxTokens == original.maxTokens)
    #expect(updated.stream == original.stream)
    #expect(updated.messages.count == original.messages.count)
}

@Test func withReasoningEffortSetsToNil() throws {
    let original = CopilotChatRequest(
        model: "gpt-5.1-codex",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hello"))
        ],
        reasoningEffort: .xhigh
    )

    let updated = original.withReasoningEffort(nil)

    #expect(updated.reasoningEffort == nil)
    #expect(updated.model == original.model)

    let data = try JSONEncoder().encode(updated)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["reasoning_effort"] == nil)
}

@Test func withReasoningEffortPreservesTools() throws {
    let original = CopilotChatRequest(
        model: "gpt-4o",
        messages: [
            ChatCompletionMessage(role: .user, content: .text("Hi"))
        ],
        tools: [
            Tool(
                type: "function",
                function: ToolFunction(name: "get_weather", description: "Get weather")
            )
        ],
        toolChoice: AnyCodable(.string("auto")),
        reasoningEffort: .xhigh
    )

    let updated = original.withReasoningEffort(.medium)

    #expect(updated.reasoningEffort == .medium)
    #expect(updated.tools?.count == 1)
    #expect(updated.tools?.first?.function.name == "get_weather")
}