import Foundation

public struct MCPRequest: Encodable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct MCPResponse: Decodable, Sendable {
    public let id: Int?
    public let result: MCPResult?
    public let error: MCPError?

    public var isSuccess: Bool { error == nil }

    public init(id: Int? = nil, result: MCPResult? = nil, error: MCPError? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case result
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int.self, forKey: .id)
        self.error = try container.decodeIfPresent(MCPError.self, forKey: .error)

        if self.error != nil {
            self.result = nil
        } else if container.contains(.result) {
            self.result = try container.decodeIfPresent(MCPResult.self, forKey: .result) ?? MCPResult()
        } else {
            self.result = MCPResult()
        }
    }
}

public struct MCPResult: Decodable, Sendable {
    public let content: [MCPContent]?
    public let tools: [MCPToolDefinition]?
    public let capabilities: MCPCapabilities?
    public let raw: [String: AnyCodable]

    public init(
        content: [MCPContent]? = nil,
        tools: [MCPToolDefinition]? = nil,
        capabilities: MCPCapabilities? = nil,
        raw: [String: AnyCodable] = [:]
    ) {
        self.content = content
        self.tools = tools
        self.capabilities = capabilities
        self.raw = raw
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    enum CodingKeys: String, CodingKey {
        case content
        case tools
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try container.decodeIfPresent([MCPContent].self, forKey: .content)
        self.tools = try container.decodeIfPresent([MCPToolDefinition].self, forKey: .tools)
        self.capabilities = try container.decodeIfPresent(MCPCapabilities.self, forKey: .capabilities)

        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var rawDict = [String: AnyCodable]()
        for key in dynamicContainer.allKeys {
            let value = try dynamicContainer.decode(AnyCodable.self, forKey: key)
            rawDict[key.stringValue] = value
        }

        rawDict = Self.patchStructuredContent(rawDict, content: self.content)

        self.raw = rawDict
    }

    private static func patchStructuredContent(
        _ raw: [String: AnyCodable],
        content: [MCPContent]?
    ) -> [String: AnyCodable] {
        guard let contentItems = content, !contentItems.isEmpty else { return raw }
        guard raw["structuredContent"] == nil else { return raw }

        guard let textItem = contentItems.first(where: { $0.type == "text" }),
              let text = textItem.text else {
            return raw
        }

        var patched = raw
        if let jsonData = text.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AnyCodable.self, from: jsonData) {
            patched["structuredContent"] = parsed
        } else {
            patched["structuredContent"] = AnyCodable(.dictionary(["text": AnyCodable(.string(text))]))
        }

        return patched
    }
}

public struct MCPContent: Decodable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

public struct MCPCapabilities: Decodable, Sendable {
    public let tools: MCPToolsCapability?

    public init(tools: MCPToolsCapability? = nil) {
        self.tools = tools
    }
}

public struct MCPToolsCapability: Decodable, Sendable {
    public let listChanged: Bool?

    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

public struct MCPError: Decodable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct MCPToolDefinition: Decodable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: [String: AnyCodable]?

    public init(name: String, description: String? = nil, inputSchema: [String: AnyCodable]? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPNotification: Encodable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodable]?

    public init(method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

enum MCPParseError: Error, CustomStringConvertible {
    case invalidJSON

    var description: String {
        switch self {
        case .invalidJSON:
            "Failed to parse MCP response as JSON"
        }
    }
}