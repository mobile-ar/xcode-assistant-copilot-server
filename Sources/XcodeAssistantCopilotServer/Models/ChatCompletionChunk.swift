import Foundation

public struct ChatCompletionChunk: Codable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [ChunkChoice]
    public let systemFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case choices
        case systemFingerprint = "system_fingerprint"
    }

    public init(
        id: String,
        object: String = "chat.completion.chunk",
        created: Int = ChatCompletionChunk.currentTimestamp(),
        model: String,
        choices: [ChunkChoice],
        systemFingerprint: String? = nil
    ) {
        self.id = id
        self.object = object
        self.created = created
        self.model = model
        self.choices = choices
        self.systemFingerprint = systemFingerprint
    }
}

public struct ChunkChoice: Codable, Sendable {
    public let index: Int
    public let delta: ChunkDelta?
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }

    public init(index: Int = 0, delta: ChunkDelta? = nil, finishReason: String? = nil) {
        self.index = index
        self.delta = delta
        self.finishReason = finishReason
    }
}

public struct ChunkDelta: Codable, Sendable {
    public let role: MessageRole?
    public let content: String?
    public let toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }

    public init(role: MessageRole? = nil, content: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
}

extension ChatCompletionChunk {
    public static func currentTimestamp() -> Int {
        Int(Date.now.timeIntervalSince1970)
    }

    public static func makeRoleDelta(id: String, model: String) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            model: model,
            choices: [ChunkChoice(delta: ChunkDelta(role: .assistant))]
        )
    }

    public static func makeContentDelta(id: String, model: String, content: String) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            model: model,
            choices: [ChunkChoice(delta: ChunkDelta(content: content))]
        )
    }

    public static func makeToolCallDelta(id: String, model: String, toolCalls: [ToolCall]) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            model: model,
            choices: [ChunkChoice(delta: ChunkDelta(toolCalls: toolCalls))]
        )
    }

    public static func makeStopDelta(id: String, model: String) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            model: model,
            choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "stop")]
        )
    }

    public static func makeCompletionId() -> String {
        "chatcmpl-\(Int(Date.now.timeIntervalSince1970 * 1000))"
    }
}