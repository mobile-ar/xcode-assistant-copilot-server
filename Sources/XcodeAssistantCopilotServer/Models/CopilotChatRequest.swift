import Foundation

public struct CopilotChatRequest: Encodable, Sendable {
    public let model: String
    public let messages: [ChatCompletionMessage]
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?
    public let stop: StopSequence?
    public let tools: [Tool]?
    public let toolChoice: AnyCodable?
    public let reasoningEffort: ReasoningEffort?
    public let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case stop
        case tools
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
        case stream
    }

    public init(
        model: String,
        messages: [ChatCompletionMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stop: StopSequence? = nil,
        tools: [Tool]? = nil,
        toolChoice: AnyCodable? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        stream: Bool = true
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stop = stop
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoningEffort = reasoningEffort
        self.stream = stream
    }

    public func withReasoningEffort(_ effort: ReasoningEffort?) -> CopilotChatRequest {
        CopilotChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            reasoningEffort: effort,
            stream: stream
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(stop, forKey: .stop)
        if let tools, !tools.isEmpty {
            try container.encode(tools, forKey: .tools)
        }
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
    }
}