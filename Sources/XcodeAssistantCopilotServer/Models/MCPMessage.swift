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

public struct MCPResponse: Sendable {
    public let id: Int?
    public let result: MCPResult?
    public let error: MCPError?

    public var isSuccess: Bool { error == nil }
}

public struct MCPResult: Sendable {
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
}

public struct MCPContent: Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

public struct MCPCapabilities: Sendable {
    public let tools: MCPToolsCapability?

    public init(tools: MCPToolsCapability? = nil) {
        self.tools = tools
    }
}

public struct MCPToolsCapability: Sendable {
    public let listChanged: Bool?

    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

public struct MCPError: Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct MCPToolDefinition: Sendable {
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

enum MCPResponseParser {
    static func parse(from data: Data) throws -> MCPResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPParseError.invalidJSON
        }

        let patchedJSON = patchStructuredContent(json)

        let id = patchedJSON["id"] as? Int

        if let errorDict = patchedJSON["error"] as? [String: Any] {
            let code = errorDict["code"] as? Int ?? -1
            let message = errorDict["message"] as? String ?? "Unknown error"
            return MCPResponse(id: id, result: nil, error: MCPError(code: code, message: message))
        }

        guard let resultDict = patchedJSON["result"] as? [String: Any] else {
            return MCPResponse(id: id, result: MCPResult(), error: nil)
        }

        let content = parseContent(from: resultDict)
        let tools = parseTools(from: resultDict)
        let capabilities = parseCapabilities(from: resultDict)
        let raw = dictionaryToAnyCodable(resultDict)

        let result = MCPResult(
            content: content,
            tools: tools,
            capabilities: capabilities,
            raw: raw
        )

        return MCPResponse(id: id, result: result, error: nil)
    }

    private static func patchStructuredContent(_ json: [String: Any]) -> [String: Any] {
        var patched = json
        guard var result = patched["result"] as? [String: Any] else { return patched }
        guard let contentArray = result["content"] as? [[String: Any]], !contentArray.isEmpty else {
            return patched
        }
        guard result["structuredContent"] == nil else { return patched }

        if let textItem = contentArray.first(where: { ($0["type"] as? String) == "text" }),
           let text = textItem["text"] as? String {
            if let jsonData = text.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) {
                result["structuredContent"] = parsed
            } else {
                result["structuredContent"] = ["text": text]
            }
            patched["result"] = result
        }

        return patched
    }

    private static func parseContent(from dict: [String: Any]) -> [MCPContent]? {
        guard let contentArray = dict["content"] as? [[String: Any]] else { return nil }
        return contentArray.map { item in
            MCPContent(
                type: item["type"] as? String ?? "text",
                text: item["text"] as? String
            )
        }
    }

    private static func parseTools(from dict: [String: Any]) -> [MCPToolDefinition]? {
        guard let toolsArray = dict["tools"] as? [[String: Any]] else { return nil }
        return toolsArray.map { item in
            let inputSchema: [String: AnyCodable]?
            if let schema = item["inputSchema"] as? [String: Any] {
                inputSchema = dictionaryToAnyCodable(schema)
            } else {
                inputSchema = nil
            }
            return MCPToolDefinition(
                name: item["name"] as? String ?? "",
                description: item["description"] as? String,
                inputSchema: inputSchema
            )
        }
    }

    private static func parseCapabilities(from dict: [String: Any]) -> MCPCapabilities? {
        guard let capDict = dict["capabilities"] as? [String: Any] else { return nil }
        let toolsCap: MCPToolsCapability?
        if let toolsDict = capDict["tools"] as? [String: Any] {
            toolsCap = MCPToolsCapability(listChanged: toolsDict["listChanged"] as? Bool)
        } else {
            toolsCap = nil
        }
        return MCPCapabilities(tools: toolsCap)
    }

    private static func dictionaryToAnyCodable(_ dict: [String: Any]) -> [String: AnyCodable] {
        dict.compactMapValues { anyToAnyCodable($0) }
    }

    private static func anyToAnyCodable(_ value: Any) -> AnyCodable {
        switch value {
        case let string as String:
            AnyCodable(.string(string))
        case let int as Int:
            AnyCodable(.int(int))
        case let double as Double:
            AnyCodable(.double(double))
        case let bool as Bool:
            AnyCodable(.bool(bool))
        case let array as [Any]:
            AnyCodable(.array(array.map { anyToAnyCodable($0) }))
        case let dict as [String: Any]:
            AnyCodable(.dictionary(dictionaryToAnyCodable(dict)))
        default:
            AnyCodable(.null)
        }
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