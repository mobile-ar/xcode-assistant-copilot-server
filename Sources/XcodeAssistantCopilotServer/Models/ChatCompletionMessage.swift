import Foundation

public enum MessageRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
    case tool
}

public struct ContentPart: Codable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

public enum MessageContent: Codable, Sendable {
    case text(String)
    case parts([ContentPart])
    case none

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
        } else if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let parts = try? container.decode([ContentPart].self) {
            self = .parts(parts)
        } else {
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        case .none:
            try container.encodeNil()
        }
    }
}

public struct ToolCallFunction: Codable, Sendable {
    public let name: String
    public let arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolCall: Codable, Sendable {
    public let index: Int?
    public let id: String?
    public let type: String?
    public let function: ToolCallFunction

    public init(index: Int? = nil, id: String? = nil, type: String? = nil, function: ToolCallFunction) {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct ChatCompletionMessage: Codable, Sendable {
    public let role: MessageRole?
    public let content: MessageContent?
    public let name: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    public init(
        role: MessageRole? = nil,
        content: MessageContent? = nil,
        name: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

public enum ContentExtractionError: Error, CustomStringConvertible {
    case unsupportedContentType(String)
    case missingTextField

    public var description: String {
        switch self {
        case .unsupportedContentType(let type):
            "Unsupported content type: \(type)"
        case .missingTextField:
            "Text content part missing required 'text' field"
        }
    }
}

extension ChatCompletionMessage {
    public func extractContentText() throws -> String {
        guard let content else { return "" }

        switch content {
        case .none:
            return ""
        case .text(let text):
            return text
        case .parts(let parts):
            var result = ""
            for part in parts {
                guard part.type == "text" else {
                    throw ContentExtractionError.unsupportedContentType(part.type)
                }
                guard let text = part.text else {
                    throw ContentExtractionError.missingTextField
                }
                result += text
            }
            return result
        }
    }
}