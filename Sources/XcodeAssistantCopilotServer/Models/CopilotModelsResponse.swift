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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        capabilities = try? container.decodeIfPresent(CopilotModelCapabilities.self, forKey: .capabilities)
        supportedEndpoints = try? container.decodeIfPresent([String].self, forKey: .supportedEndpoints)
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

    enum CodingKeys: String, CodingKey {
        case family
        case type
        case supports
    }

    public init(family: String? = nil, type: String? = nil, supports: CopilotModelSupports? = nil) {
        self.family = family
        self.type = type
        self.supports = supports
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(String.self, forKey: .family)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        supports = try? container.decodeIfPresent(CopilotModelSupports.self, forKey: .supports)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reasoningEffort = Self.decodeBoolFlexibly(from: container, key: .reasoningEffort)
        streaming = Self.decodeBoolFlexibly(from: container, key: .streaming)
        toolCalls = Self.decodeBoolFlexibly(from: container, key: .toolCalls)
        parallelToolCalls = Self.decodeBoolFlexibly(from: container, key: .parallelToolCalls)
        structuredOutputs = Self.decodeBoolFlexibly(from: container, key: .structuredOutputs)
        vision = Self.decodeBoolFlexibly(from: container, key: .vision)
    }

    private static func decodeBoolFlexibly(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool? {
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return boolValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue != 0
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            switch stringValue.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
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

    enum CodingKeys: String, CodingKey {
        case data
        case models
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = Self.decodeLenientArray(from: container, key: .data)
        models = Self.decodeLenientArray(from: container, key: .models)
    }

    private static func decodeLenientArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [CopilotModel]? {
        guard var arrayContainer = try? container.nestedUnkeyedContainer(forKey: key) else {
            return nil
        }
        var result: [CopilotModel] = []
        while !arrayContainer.isAtEnd {
            if let model = try? arrayContainer.decode(CopilotModel.self) {
                result.append(model)
            } else {
                _ = try? arrayContainer.decode(AnyCodable.self)
            }
        }
        return result
    }
}