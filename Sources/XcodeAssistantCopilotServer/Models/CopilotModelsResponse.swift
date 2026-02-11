import Foundation

public struct CopilotModel: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let version: String?
    public let capabilities: CopilotModelCapabilities?

    public init(id: String, name: String? = nil, version: String? = nil, capabilities: CopilotModelCapabilities? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.capabilities = capabilities
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

    enum CodingKeys: String, CodingKey {
        case reasoningEffort = "reasoning_effort"
    }

    public init(reasoningEffort: Bool? = nil) {
        self.reasoningEffort = reasoningEffort
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