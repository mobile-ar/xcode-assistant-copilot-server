import Foundation

public struct CopilotModel: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let version: String?
    public let capabilities: CopilotModelCapabilities?
    public let supportedEndpoints: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case capabilities
        case supportedEndpoints = "supported_endpoints"
    }

    public init(
        id: String,
        name: String? = nil,
        version: String? = nil,
        capabilities: CopilotModelCapabilities? = nil,
        supportedEndpoints: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.capabilities = capabilities
        self.supportedEndpoints = supportedEndpoints
    }

    public var requiresResponsesAPI: Bool {
        guard let endpoints = supportedEndpoints else { return false }
        return endpoints.contains("/responses") && !endpoints.contains("/chat/completions")
    }

    public var supportsResponsesAPI: Bool {
        supportedEndpoints?.contains("/responses") ?? false
    }

    public var supportsChatCompletions: Bool {
        guard let endpoints = supportedEndpoints else { return true }
        return endpoints.contains("/chat/completions")
    }
}

public struct CopilotModelCapabilities: Decodable, Sendable {
    public let family: String?
    public let type: String?
    public let supports: CopilotModelSupports?

    public init(family: String? = nil, type: String? = nil, supports: CopilotModelSupports? = nil) {
        self.family = family
        self.type = type
        self.supports = supports
    }
}

public struct CopilotModelSupports: Decodable, Sendable {
    public let reasoningEffort: Bool?
    public let streaming: Bool?
    public let toolCalls: Bool?
    public let parallelToolCalls: Bool?
    public let structuredOutputs: Bool?
    public let vision: Bool?

    enum CodingKeys: String, CodingKey {
        case reasoningEffort = "reasoning_effort"
        case streaming
        case toolCalls = "tool_calls"
        case parallelToolCalls = "parallel_tool_calls"
        case structuredOutputs = "structured_outputs"
        case vision
    }

    public init(
        reasoningEffort: Bool? = nil,
        streaming: Bool? = nil,
        toolCalls: Bool? = nil,
        parallelToolCalls: Bool? = nil,
        structuredOutputs: Bool? = nil,
        vision: Bool? = nil
    ) {
        self.reasoningEffort = reasoningEffort
        self.streaming = streaming
        self.toolCalls = toolCalls
        self.parallelToolCalls = parallelToolCalls
        self.structuredOutputs = structuredOutputs
        self.vision = vision
    }
}

public struct CopilotModelsResponse: Decodable, Sendable {
    public let data: [CopilotModel]?
    public let models: [CopilotModel]?

    public var allModels: [CopilotModel] {
        data ?? models ?? []
    }

    public init(data: [CopilotModel]? = nil, models: [CopilotModel]? = nil) {
        self.data = data
        self.models = models
    }
}