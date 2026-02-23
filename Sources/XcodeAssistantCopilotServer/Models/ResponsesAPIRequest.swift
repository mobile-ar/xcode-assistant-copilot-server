import Foundation

public struct ResponsesAPIRequest: Encodable, Sendable {
    public let model: String
    public let input: [ResponsesInputItem]
    public let stream: Bool
    public let instructions: String?
    public let tools: [ResponsesAPITool]?
    public let toolChoice: AnyCodable?
    public let reasoning: ResponsesReasoning?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case stream
        case instructions
        case tools
        case toolChoice = "tool_choice"
        case reasoning
    }

    public init(
        model: String,
        input: [ResponsesInputItem],
        stream: Bool = true,
        instructions: String? = nil,
        tools: [ResponsesAPITool]? = nil,
        toolChoice: AnyCodable? = nil,
        reasoning: ResponsesReasoning? = nil
    ) {
        self.model = model
        self.input = input
        self.stream = stream
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoning = reasoning
    }
}

public enum ResponsesInputItem: Sendable {
    case message(ResponsesMessage)
    case functionCall(ResponsesFunctionCall)
    case functionCallOutput(ResponsesFunctionCallOutput)
}

extension ResponsesInputItem: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .functionCall(let call):
            try call.encode(to: encoder)
        case .functionCallOutput(let output):
            try output.encode(to: encoder)
        }
    }
}

public struct ResponsesMessage: Encodable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ResponsesFunctionCall: Encodable, Sendable {
    public let type: String
    public let id: String
    public let callId: String
    public let name: String
    public let arguments: String

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callId = "call_id"
        case name
        case arguments
    }

    public init(id: String, callId: String, name: String, arguments: String) {
        self.type = "function_call"
        self.id = id
        self.callId = callId
        self.name = name
        self.arguments = arguments
    }
}

public struct ResponsesFunctionCallOutput: Encodable, Sendable {
    public let type: String
    public let callId: String
    public let output: String

    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }

    public init(callId: String, output: String) {
        self.type = "function_call_output"
        self.callId = callId
        self.output = output
    }
}

public struct ResponsesAPITool: Encodable, Sendable {
    public let type: String
    public let name: String
    public let description: String?
    public let parameters: [String: AnyCodable]?

    public init(
        name: String,
        description: String? = nil,
        parameters: [String: AnyCodable]? = nil
    ) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ResponsesReasoning: Encodable, Sendable {
    public let effort: String

    public init(effort: String) {
        self.effort = effort
    }
}