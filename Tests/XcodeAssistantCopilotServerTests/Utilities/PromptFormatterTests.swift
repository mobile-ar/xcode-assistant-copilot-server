import Testing
@testable import XcodeAssistantCopilotServer

@Test func formatPromptWithUserMessage() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .user, content: .text("Hello, world!")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[User]: Hello, world!")
}

@Test func formatPromptWithAssistantMessage() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .assistant, content: .text("Hi there!")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[Assistant]: Hi there!")
}

@Test func formatPromptWithToolMessage() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(
            role: .tool,
            content: .text("search result"),
            toolCallId: "call_123"
        ),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[Tool result for call_123]: search result")
}

@Test func formatPromptWithToolMessageMissingId() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .tool, content: .text("result")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[Tool result for unknown]: result")
}

@Test func formatPromptSkipsSystemMessages() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .system, content: .text("You are a helpful assistant.")),
        ChatCompletionMessage(role: .user, content: .text("Hello")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[User]: Hello")
}

@Test func formatPromptSkipsDeveloperMessages() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .developer, content: .text("Instructions")),
        ChatCompletionMessage(role: .user, content: .text("Hi")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[User]: Hi")
}

@Test func formatPromptWithMultipleMessages() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .system, content: .text("System prompt")),
        ChatCompletionMessage(role: .user, content: .text("What is Swift?")),
        ChatCompletionMessage(role: .assistant, content: .text("Swift is a programming language.")),
        ChatCompletionMessage(role: .user, content: .text("Tell me more.")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    let expected = "[User]: What is Swift?\n\n[Assistant]: Swift is a programming language.\n\n[User]: Tell me more."
    #expect(result == expected)
}

@Test func formatPromptWithAssistantToolCalls() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(
            role: .assistant,
            content: MessageContent.none,
            toolCalls: [
                ToolCall(
                    index: 0,
                    id: "call_1",
                    type: "function",
                    function: ToolCallFunction(name: "search", arguments: "{\"query\":\"swift\"}")
                ),
            ]
        ),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[Assistant called tool search with args: {\"query\":\"swift\"}]")
}

@Test func formatPromptWithAssistantContentAndToolCalls() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(
            role: .assistant,
            content: .text("Let me search for that."),
            toolCalls: [
                ToolCall(
                    index: 0,
                    id: "call_1",
                    type: "function",
                    function: ToolCallFunction(name: "grep", arguments: "{\"pattern\":\"func\"}")
                ),
            ]
        ),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    let expected = "[Assistant]: Let me search for that.\n\n[Assistant called tool grep with args: {\"pattern\":\"func\"}]"
    #expect(result == expected)
}

@Test func formatPromptWithEmptyMessages() throws {
    let formatter = PromptFormatter()
    let result = try formatter.formatPrompt(messages: [])
    #expect(result == "")
}

@Test func formatPromptWithNilRole() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: nil, content: .text("orphan message")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "")
}

@Test func formatPromptWithEmptyAssistantContent() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .assistant, content: .text("")),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "")
}

@Test func extractSystemMessagesFromMixed() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .system, content: .text("You are helpful.")),
        ChatCompletionMessage(role: .user, content: .text("Hi")),
        ChatCompletionMessage(role: .developer, content: .text("Be concise.")),
    ]

    let result = try formatter.extractSystemMessages(from: messages)
    #expect(result == "You are helpful.\n\nBe concise.")
}

@Test func extractSystemMessagesReturnsNilWhenNone() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .user, content: .text("Hi")),
    ]

    let result = try formatter.extractSystemMessages(from: messages)
    #expect(result == nil)
}

@Test func extractSystemMessagesSkipsEmptyContent() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .system, content: .text("")),
        ChatCompletionMessage(role: .developer, content: .text("Instructions")),
    ]

    let result = try formatter.extractSystemMessages(from: messages)
    #expect(result == "Instructions")
}

@Test func extractSystemMessagesReturnsNilWhenAllEmpty() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(role: .system, content: .text("")),
        ChatCompletionMessage(role: .system, content: MessageContent.none),
    ]

    let result = try formatter.extractSystemMessages(from: messages)
    #expect(result == nil)
}

@Test func filterExcludedFilesWithNoPatterns() {
    let formatter = PromptFormatter()
    let text = "some text with ```swift:/path/to/File.swift\ncode\n```\n"
    let result = formatter.filterExcludedFiles(text, patterns: [])
    #expect(result == text)
}

@Test func filterExcludedFilesRemovesMatchingBlock() {
    let formatter = PromptFormatter()
    let text = "before\n```swift:/path/to/MockFile.swift\nmock code here\n```\nafter"
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(result.contains("before"))
    #expect(result.contains("after"))
    #expect(!result.contains("mock code here"))
}

@Test func filterExcludedFilesKeepsNonMatchingBlock() {
    let formatter = PromptFormatter()
    let text = "before\n```swift:/path/to/RealFile.swift\nreal code\n```\nafter"
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(result.contains("real code"))
}

@Test func filterExcludedFilesIsCaseInsensitive() {
    let formatter = PromptFormatter()
    let text = "```swift:/path/to/MOCKDATA.swift\ndata\n```\n"
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(!result.contains("data"))
}

@Test func filterExcludedFilesRequiresColonInHeader() {
    let formatter = PromptFormatter()
    let text = "```swift\nsome swift code\n```\nrest"
    let result = formatter.filterExcludedFiles(text, patterns: ["swift"])
    #expect(result.contains("some swift code"))
}

@Test func filterExcludedFilesHandlesMultiplePatterns() {
    let formatter = PromptFormatter()
    let text = """
    start
    ```swift:/path/MockFile.swift
    mock code
    ```
    middle
    ```swift:/path/GeneratedFile.swift
    generated code
    ```
    ```swift:/path/RealFile.swift
    real code
    ```
    end
    """
    let result = formatter.filterExcludedFiles(text, patterns: ["mock", "generated"])
    #expect(!result.contains("mock code"))
    #expect(!result.contains("generated code"))
    #expect(result.contains("real code"))
    #expect(result.contains("start"))
    #expect(result.contains("middle"))
    #expect(result.contains("end"))
}

@Test func filterExcludedFilesHandlesEmptyText() {
    let formatter = PromptFormatter()
    let result = formatter.filterExcludedFiles("", patterns: ["mock"])
    #expect(result == "")
}

@Test func filterExcludedFilesHandlesTextWithNoCodeBlocks() {
    let formatter = PromptFormatter()
    let text = "Just some normal text without any code blocks."
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(result == text)
}

@Test func formatPromptWithExcludedFilePatterns() throws {
    let formatter = PromptFormatter()
    let userContent = "Here is a search result:\n```swift:/path/MockData.swift\nmock stuff\n```\nAnd real code:\n```swift:/path/App.swift\nreal code\n```\n"
    let messages = [
        ChatCompletionMessage(role: .user, content: .text(userContent)),
    ]

    let result = try formatter.formatPrompt(messages: messages, excludedFilePatterns: ["mock"])
    #expect(!result.contains("mock stuff"))
    #expect(result.contains("real code"))
}

@Test func formatPromptWithContentParts() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(
            role: .user,
            content: .parts([
                ContentPart(type: "text", text: "Hello "),
                ContentPart(type: "text", text: "world!"),
            ])
        ),
    ]

    let result = try formatter.formatPrompt(messages: messages)
    #expect(result == "[User]: Hello world!")
}

@Test func formatPromptThrowsOnUnsupportedContentPart() throws {
    let formatter = PromptFormatter()
    let messages = [
        ChatCompletionMessage(
            role: .user,
            content: .parts([
                ContentPart(type: "image_url", text: nil),
            ])
        ),
    ]

    #expect(throws: PromptFormatterError.self) {
        try formatter.formatPrompt(messages: messages)
    }
}

@Test func filterExcludedFilesHandlesUnclosedCodeBlock() {
    let formatter = PromptFormatter()
    let text = "before\n```swift:/path/MockFile.swift\nunclosed block"
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(result.contains("unclosed block"))
}

@Test func filterExcludedFilesHandlesMultipleConsecutiveBlocks() {
    let formatter = PromptFormatter()
    let text = """
    ```swift:/path/Mock1.swift
    mock1
    ```
    ```swift:/path/Mock2.swift
    mock2
    ```
    """
    let result = formatter.filterExcludedFiles(text, patterns: ["mock"])
    #expect(!result.contains("mock1"))
    #expect(!result.contains("mock2"))
}