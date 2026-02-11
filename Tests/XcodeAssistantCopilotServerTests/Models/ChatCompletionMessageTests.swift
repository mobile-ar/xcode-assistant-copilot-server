import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func extractContentTextFromStringContent() throws {
    let message = ChatCompletionMessage(role: .user, content: .text("Hello, world!"))
    let result = try message.extractContentText()
    #expect(result == "Hello, world!")
}

@Test func extractContentTextFromNoneContent() throws {
    let message = ChatCompletionMessage(role: .assistant, content: MessageContent.none)
    let result = try message.extractContentText()
    #expect(result == "")
}

@Test func extractContentTextFromNilContent() throws {
    let message = ChatCompletionMessage(role: .assistant, content: nil)
    let result = try message.extractContentText()
    #expect(result == "")
}

@Test func extractContentTextFromSingleTextPart() throws {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "text", text: "Hello!")])
    )
    let result = try message.extractContentText()
    #expect(result == "Hello!")
}

@Test func extractContentTextFromMultipleTextParts() throws {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([
            ContentPart(type: "text", text: "Hello, "),
            ContentPart(type: "text", text: "world!"),
        ])
    )
    let result = try message.extractContentText()
    #expect(result == "Hello, world!")
}

@Test func extractContentTextThrowsOnUnsupportedPartType() {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "image_url", text: nil)])
    )
    #expect(throws: ContentExtractionError.self) {
        try message.extractContentText()
    }
}

@Test func extractContentTextThrowsUnsupportedContentTypeWithCorrectType() {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "audio", text: nil)])
    )
    do {
        _ = try message.extractContentText()
        Issue.record("Expected ContentExtractionError.unsupportedContentType")
    } catch let error as ContentExtractionError {
        switch error {
        case .unsupportedContentType(let type):
            #expect(type == "audio")
        case .missingTextField:
            Issue.record("Expected unsupportedContentType, got missingTextField")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func extractContentTextThrowsOnMissingTextField() {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "text", text: nil)])
    )
    #expect(throws: ContentExtractionError.self) {
        try message.extractContentText()
    }
}

@Test func extractContentTextThrowsMissingTextFieldError() {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "text", text: nil)])
    )
    do {
        _ = try message.extractContentText()
        Issue.record("Expected ContentExtractionError.missingTextField")
    } catch let error as ContentExtractionError {
        switch error {
        case .missingTextField:
            break
        case .unsupportedContentType:
            Issue.record("Expected missingTextField, got unsupportedContentType")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func extractContentTextFromEmptyParts() throws {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([])
    )
    let result = try message.extractContentText()
    #expect(result == "")
}

@Test func extractContentTextFromEmptyString() throws {
    let message = ChatCompletionMessage(role: .user, content: .text(""))
    let result = try message.extractContentText()
    #expect(result == "")
}

@Test func extractContentTextConcatenatesMultipleParts() throws {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([
            ContentPart(type: "text", text: "First. "),
            ContentPart(type: "text", text: "Second. "),
            ContentPart(type: "text", text: "Third."),
        ])
    )
    let result = try message.extractContentText()
    #expect(result == "First. Second. Third.")
}

@Test func extractContentTextThrowsOnMixedPartsWithUnsupported() {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([
            ContentPart(type: "text", text: "valid"),
            ContentPart(type: "image_url", text: nil),
        ])
    )
    #expect(throws: ContentExtractionError.self) {
        try message.extractContentText()
    }
}

@Test func messageContentDecodesFromString() throws {
    let json = """
    {"role":"user","content":"Hello"}
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.role == .user)
    let text = try message.extractContentText()
    #expect(text == "Hello")
}

@Test func messageContentDecodesFromNull() throws {
    let json = """
    {"role":"assistant","content":null}
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.role == .assistant)
    let text = try message.extractContentText()
    #expect(text == "")
}

@Test func messageContentDecodesFromArray() throws {
    let json = """
    {"role":"user","content":[{"type":"text","text":"Hello from array"}]}
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    let text = try message.extractContentText()
    #expect(text == "Hello from array")
}

@Test func messageContentDecodesWithoutContent() throws {
    let json = """
    {"role":"assistant"}
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.role == .assistant)
    let text = try message.extractContentText()
    #expect(text == "")
}

@Test func messageRoleDecodesCorrectly() throws {
    let roles: [(String, MessageRole)] = [
        ("system", .system),
        ("developer", .developer),
        ("user", .user),
        ("assistant", .assistant),
        ("tool", .tool),
    ]
    for (raw, expected) in roles {
        let json = """
        {"role":"\(raw)","content":"test"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
        #expect(message.role == expected)
    }
}

@Test func messageWithToolCallsDecodes() throws {
    let json = """
    {
        "role": "assistant",
        "content": null,
        "tool_calls": [
            {
                "index": 0,
                "id": "call_abc123",
                "type": "function",
                "function": {
                    "name": "search_files",
                    "arguments": "{\\"query\\":\\"test\\"}"
                }
            }
        ]
    }
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.role == .assistant)
    #expect(message.toolCalls?.count == 1)
    #expect(message.toolCalls?.first?.id == "call_abc123")
    #expect(message.toolCalls?.first?.function.name == "search_files")
    #expect(message.toolCalls?.first?.function.arguments == "{\"query\":\"test\"}")
    #expect(message.toolCalls?.first?.index == 0)
    #expect(message.toolCalls?.first?.type == "function")
}

@Test func messageWithToolCallIdDecodes() throws {
    let json = """
    {
        "role": "tool",
        "content": "search result data",
        "tool_call_id": "call_abc123"
    }
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.role == .tool)
    #expect(message.toolCallId == "call_abc123")
    let text = try message.extractContentText()
    #expect(text == "search result data")
}

@Test func messageEncodesAndDecodesRoundTrip() throws {
    let original = ChatCompletionMessage(
        role: .user,
        content: .text("Round trip test"),
        name: "test_user"
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(decoded.role == original.role)
    #expect(decoded.name == original.name)
    let originalText = try original.extractContentText()
    let decodedText = try decoded.extractContentText()
    #expect(originalText == decodedText)
}

@Test func messageWithMultipleToolCallsDecodes() throws {
    let json = """
    {
        "role": "assistant",
        "content": null,
        "tool_calls": [
            {
                "index": 0,
                "id": "call_1",
                "type": "function",
                "function": {
                    "name": "search",
                    "arguments": "{\\"q\\":\\"a\\"}"
                }
            },
            {
                "index": 1,
                "id": "call_2",
                "type": "function",
                "function": {
                    "name": "read_file",
                    "arguments": "{\\"path\\":\\"foo.swift\\"}"
                }
            }
        ]
    }
    """
    let data = json.data(using: .utf8)!
    let message = try JSONDecoder().decode(ChatCompletionMessage.self, from: data)
    #expect(message.toolCalls?.count == 2)
    #expect(message.toolCalls?[0].function.name == "search")
    #expect(message.toolCalls?[1].function.name == "read_file")
}

@Test func contentExtractionErrorDescriptions() {
    let unsupported = ContentExtractionError.unsupportedContentType("image_url")
    #expect(unsupported.description.contains("image_url"))

    let missing = ContentExtractionError.missingTextField
    #expect(missing.description.contains("text"))
}

@Test func messageContentEncodesTextCorrectly() throws {
    let message = ChatCompletionMessage(role: .user, content: .text("Encoded text"))
    let data = try JSONEncoder().encode(message)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["content"] as? String == "Encoded text")
}

@Test func messageContentEncodesNoneAsNull() throws {
    let message = ChatCompletionMessage(role: .assistant, content: MessageContent.none)
    let data = try JSONEncoder().encode(message)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["content"] is NSNull)
}

@Test func messageContentEncodesPartsAsArray() throws {
    let message = ChatCompletionMessage(
        role: .user,
        content: .parts([ContentPart(type: "text", text: "part1")])
    )
    let data = try JSONEncoder().encode(message)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let contentArray = json?["content"] as? [[String: Any]]
    #expect(contentArray?.count == 1)
    #expect(contentArray?.first?["type"] as? String == "text")
    #expect(contentArray?.first?["text"] as? String == "part1")
}