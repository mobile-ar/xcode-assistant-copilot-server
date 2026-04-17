@testable import XcodeAssistantCopilotServer
import Testing

struct ConversationContextManagerTests {
    private let logger = MockLogger()
    private let sut: ConversationContextManager

    init() {
        sut = ConversationContextManager(logger: logger)
    }

    @Test
    func compactPreservesSystemAndDeveloperMessages() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("You are a helpful assistant.")),
            ChatCompletionMessage(role: .developer, content: .text("Follow these rules.")),
            ChatCompletionMessage(role: .user, content: .text("Hello")),
            ChatCompletionMessage(role: .assistant, content: .text("Hi there")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 10, recencyWindow: 0)

        #expect(result.count == 4)
        #expect(extractText(result[0]) == "You are a helpful assistant.")
        #expect(extractText(result[1]) == "Follow these rules.")
    }

    @Test
    func compactPreservesLastUserMessage() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System prompt")),
            ChatCompletionMessage(role: .user, content: .text("First question")),
            ChatCompletionMessage(role: .assistant, content: .text("First answer")),
            ChatCompletionMessage(role: .user, content: .text("Second question with lots of detail")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 10, recencyWindow: 0)

        #expect(extractText(result[3]) == "Second question with lots of detail")
    }

    @Test
    func compactPreservesRecentAssistantToolPairs() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "old_1", type: "function", function: ToolCallFunction(name: "old_tool", arguments: "{\"key\":\"old_value\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Old tool result with lots of text"), toolCallId: "old_1"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "recent_1", type: "function", function: ToolCallFunction(name: "recent_tool", arguments: "{\"key\":\"recent_value\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Recent tool result"), toolCallId: "recent_1"),
            ChatCompletionMessage(role: .user, content: .text("Follow up")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        #expect(extractText(result[4]) == "Recent tool result")

        let recentAssistantCalls = result[3].toolCalls
        #expect(recentAssistantCalls?.first?.function.arguments == "{\"key\":\"recent_value\"}")
    }

    @Test
    func compactTruncatesOlderToolResults() {
        let toolResultText = "This is a long tool result with 48 characters!!"
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_1", type: "function", function: ToolCallFunction(name: "read_file", arguments: "{\"path\":\"file.txt\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text(toolResultText), toolCallId: "call_1"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_2", type: "function", function: ToolCallFunction(name: "write_file", arguments: "{\"path\":\"out.txt\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Recent result"), toolCallId: "call_2"),
            ChatCompletionMessage(role: .user, content: .text("Done?")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        let truncatedTool = result[2]
        #expect(truncatedTool.role == .tool)
        let truncatedText = extractText(truncatedTool)
        #expect(truncatedText == "[Result truncated — original \(toolResultText.count) chars]")
        #expect(truncatedTool.toolCallId == "call_1")
    }

    @Test
    func compactStripsOlderToolCallArguments() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "old_call", type: "function", function: ToolCallFunction(name: "search", arguments: "{\"query\":\"something very long and detailed\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Search results"), toolCallId: "old_call"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "new_call", type: "function", function: ToolCallFunction(name: "confirm", arguments: "{\"ok\":true}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Confirmed"), toolCallId: "new_call"),
            ChatCompletionMessage(role: .user, content: .text("Thanks")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        let oldAssistant = result[1]
        #expect(oldAssistant.toolCalls?.count == 1)
        #expect(oldAssistant.toolCalls?.first?.function.name == "search")
        #expect(oldAssistant.toolCalls?.first?.function.arguments == "{}")
        #expect(oldAssistant.toolCalls?.first?.id == "old_call")
    }

    @Test
    func compactKeepsRegularOlderMessagesInFull() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .user, content: .text("First user message")),
            ChatCompletionMessage(role: .assistant, content: .text("First assistant reply")),
            ChatCompletionMessage(role: .user, content: .text("Second user message")),
            ChatCompletionMessage(role: .assistant, content: .text("Second assistant reply")),
            ChatCompletionMessage(role: .user, content: .text("Third user message")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 100_000, recencyWindow: 0)

        #expect(result.count == 6)
        #expect(extractText(result[1]) == "First user message")
        #expect(extractText(result[2]) == "First assistant reply")
        #expect(extractText(result[4]) == "Second assistant reply")
    }

    @Test
    func compactLogsWarningWhenStillOverLimit() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text(String(repeating: "x", count: 400))),
            ChatCompletionMessage(role: .user, content: .text(String(repeating: "y", count: 400))),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 10, recencyWindow: 0)

        #expect(result.count == 2)
        #expect(logger.warnMessages.count == 1)
        #expect(logger.warnMessages.first?.contains("still exceeds token limit") == true)
    }

    @Test
    func compactDoesNotLogWarningWhenUnderLimit() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("Short")),
            ChatCompletionMessage(role: .user, content: .text("Hi")),
        ]

        _ = sut.compact(messages: messages, tokenLimit: 100_000, recencyWindow: 0)

        #expect(logger.warnMessages.isEmpty)
    }

    @Test
    func compactSkipsCompactionWhenUnderTokenLimit() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_1", type: "function", function: ToolCallFunction(name: "read_file", arguments: "{\"path\":\"file.txt\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("File contents here"), toolCallId: "call_1"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_2", type: "function", function: ToolCallFunction(name: "write_file", arguments: "{\"content\":\"new stuff\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("File written successfully"), toolCallId: "call_2"),
            ChatCompletionMessage(role: .user, content: .text("Thanks")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 100_000, recencyWindow: 1)

        #expect(result.count == 6)
        #expect(extractText(result[2]) == "File contents here")
        #expect(result[1].toolCalls?.first?.function.arguments == "{\"path\":\"file.txt\"}")
        #expect(extractText(result[4]) == "File written successfully")
        #expect(result[3].toolCalls?.first?.function.arguments == "{\"content\":\"new stuff\"}")
        #expect(logger.infoMessages.isEmpty)
    }

    @Test
    func compactPreservesPreviewForLongToolResults() {
        let longContent = String(repeating: "A", count: 500)
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_1", type: "function", function: ToolCallFunction(name: "read_file", arguments: "{\"path\":\"big.txt\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text(longContent), toolCallId: "call_1"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_2", type: "function", function: ToolCallFunction(name: "done", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("ok"), toolCallId: "call_2"),
            ChatCompletionMessage(role: .user, content: .text("Next")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        let truncatedText = extractText(result[2])!
        let expectedPreview = String(repeating: "A", count: 200)
        #expect(truncatedText.hasPrefix(expectedPreview))
        #expect(truncatedText.contains("[Result truncated — original \(longContent.count) chars]"))
    }

    @Test
    func compactKeepsVeryShortToolResultsUnchangedDuringCompaction() {
        let shortResult = "OK"
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_1", type: "function", function: ToolCallFunction(name: "confirm", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text(shortResult), toolCallId: "call_1"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_2", type: "function", function: ToolCallFunction(name: "finish", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Done"), toolCallId: "call_2"),
            ChatCompletionMessage(role: .user, content: .text("Thanks")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        #expect(extractText(result[2]) == shortResult)
    }

    @Test
    func compactLogsInfoWhenCompactionTriggered() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text(String(repeating: "x", count: 400))),
            ChatCompletionMessage(role: .user, content: .text("Question")),
        ]

        _ = sut.compact(messages: messages, tokenLimit: 10, recencyWindow: 0)

        #expect(logger.infoMessages.contains { $0.contains("Compacting conversation") })
    }

    @Test
    func estimateTokenCountForMessages() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .user, content: .text("Hello world")),
        ]

        let tokens = sut.estimateTokenCount(messages: messages)

        let expectedChars = "Hello world".count + "user".count
        #expect(tokens == expectedChars / 4)
    }

    @Test
    func estimateTokenCountIncludesToolCallArguments() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "1", type: "function", function: ToolCallFunction(name: "read", arguments: "{\"path\":\"test.txt\"}")),
            ]),
        ]

        let tokens = sut.estimateTokenCount(messages: messages)

        let expectedChars = "assistant".count + "{\"path\":\"test.txt\"}".count + "read".count
        #expect(tokens == expectedChars / 4)
    }

    @Test
    func estimateTokenCountHandlesPartsContent() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .user, content: .parts([
                ContentPart(type: "text", text: "Part one"),
                ContentPart(type: "text", text: "Part two"),
            ])),
        ]

        let tokens = sut.estimateTokenCount(messages: messages)

        let expectedChars = "Part one".count + "Part two".count + "user".count
        #expect(tokens == expectedChars / 4)
    }

    @Test
    func estimateTokenCountHandlesNoneContent() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .assistant, content: MessageContent.none),
        ]

        let tokens = sut.estimateTokenCount(messages: messages)

        #expect(tokens == "assistant".count / 4)
    }

    @Test
    func estimateTokenCountForTools() {
        let tools: [Tool] = [
            Tool(type: "function", function: ToolFunction(name: "read_file", description: "Reads a file", parameters: nil)),
        ]

        let tokens = sut.estimateTokenCount(tools: tools)

        #expect(tokens > 0)
    }

    @Test
    func estimateTokenCountForEmptyTools() {
        let tools: [Tool] = []

        let tokens = sut.estimateTokenCount(tools: tools)

        #expect(tokens >= 0)
    }

    @Test
    func compactWithEmptyMessages() {
        let result = sut.compact(messages: [], tokenLimit: 1000, recencyWindow: 5)

        #expect(result.isEmpty)
    }

    @Test
    func compactPreservesMultipleToolResultsForRecentAssistant() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_a", type: "function", function: ToolCallFunction(name: "tool_a", arguments: "{}")),
                ToolCall(id: "call_b", type: "function", function: ToolCallFunction(name: "tool_b", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Result A"), toolCallId: "call_a"),
            ChatCompletionMessage(role: .tool, content: .text("Result B"), toolCallId: "call_b"),
            ChatCompletionMessage(role: .user, content: .text("Next")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        #expect(extractText(result[2]) == "Result A")
        #expect(extractText(result[3]) == "Result B")
    }

    @Test
    func compactWithRecencyWindowLargerThanAvailablePairs() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_1", type: "function", function: ToolCallFunction(name: "only_tool", arguments: "{\"big\":\"args\"}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Only result"), toolCallId: "call_1"),
            ChatCompletionMessage(role: .user, content: .text("Done")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 100_000, recencyWindow: 10)

        #expect(extractText(result[2]) == "Only result")
        #expect(result[1].toolCalls?.first?.function.arguments == "{\"big\":\"args\"}")
    }

    @Test
    func compactPreservesToolCallIdOnTruncatedToolMessages() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_old", type: "function", function: ToolCallFunction(name: "tool", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Some old result"), name: "tool", toolCallId: "call_old"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_new", type: "function", function: ToolCallFunction(name: "tool2", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("New result"), toolCallId: "call_new"),
            ChatCompletionMessage(role: .user, content: .text("Ok")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        let truncated = result[2]
        #expect(truncated.toolCallId == "call_old")
        #expect(truncated.name == "tool")
    }

    @Test
    func compactPreservesToolCallMetadata() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .system, content: .text("System")),
            ChatCompletionMessage(role: .assistant, content: .text("Let me help"), toolCalls: [
                ToolCall(index: 0, id: "call_x", type: "function", function: ToolCallFunction(name: "do_thing", arguments: "{\"a\":1,\"b\":2}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Done"), toolCallId: "call_x"),
            ChatCompletionMessage(role: .assistant, content: nil, toolCalls: [
                ToolCall(id: "call_y", type: "function", function: ToolCallFunction(name: "finish", arguments: "{}")),
            ]),
            ChatCompletionMessage(role: .tool, content: .text("Finished"), toolCallId: "call_y"),
            ChatCompletionMessage(role: .user, content: .text("Great")),
        ]

        let result = sut.compact(messages: messages, tokenLimit: 1, recencyWindow: 1)

        let strippedCall = result[1].toolCalls?.first
        #expect(strippedCall?.index == 0)
        #expect(strippedCall?.id == "call_x")
        #expect(strippedCall?.type == "function")
        #expect(strippedCall?.function.name == "do_thing")
        #expect(strippedCall?.function.arguments == "{}")
    }

    @Test
    func estimateTokenCountForMessagesWithNoContent() {
        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .assistant),
        ]

        let tokens = sut.estimateTokenCount(messages: messages)

        #expect(tokens == "assistant".count / 4)
    }

    @Test
    func estimateTokenCountForEmptyMessages() {
        let tokens = sut.estimateTokenCount(messages: [])

        #expect(tokens == 0)
    }

    private func extractText(_ message: ChatCompletionMessage) -> String? {
        guard let content = message.content else { return nil }
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.compactMap(\.text).joined()
        case .none:
            return nil
        }
    }
}
