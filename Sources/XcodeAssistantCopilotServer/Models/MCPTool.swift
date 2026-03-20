import Foundation

public struct MCPTool: Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: [String: AnyCodable]?
    public let serverName: String

    public init(name: String, description: String? = nil, inputSchema: [String: AnyCodable]? = nil, serverName: String = "") {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.serverName = serverName
    }

    public func toOpenAITool() -> Tool {
        Tool(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: inputSchema
            )
        )
    }
}

extension MCPTool {
    init(from definition: MCPToolDefinition, serverName: String) {
        self.name = definition.name
        self.description = definition.description
        self.inputSchema = definition.inputSchema
        self.serverName = serverName
    }
}

public struct MCPToolResult: Sendable {
    public let content: [MCPToolResultContent]
    public let isError: Bool

    public init(content: [MCPToolResultContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public var textContent: String {
        content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
    }
}

public struct MCPToolResultContent: Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}
