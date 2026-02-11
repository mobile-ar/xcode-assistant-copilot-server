import Foundation

public enum ReasoningEffort: String, Codable, Sendable {
    case low
    case medium
    case high
    case xhigh
}

public enum PermissionKind: String, Codable, Sendable {
    case read
    case write
    case shell
    case mcp
    case url
}

public enum AutoApprovePermissions: Codable, Sendable {
    case all(Bool)
    case kinds([PermissionKind])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .all(boolValue)
        } else if let kinds = try? container.decode([PermissionKind].self) {
            self = .kinds(kinds)
        } else {
            throw DecodingError.typeMismatch(
                AutoApprovePermissions.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Bool or [PermissionKind]"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all(let value):
            try container.encode(value)
        case .kinds(let kinds):
            try container.encode(kinds)
        }
    }

    public func isApproved(_ kind: PermissionKind) -> Bool {
        switch self {
        case .all(let approved):
            approved
        case .kinds(let kinds):
            kinds.contains(kind)
        }
    }
}

public struct MCPServerConfiguration: Codable, Sendable {
    public let type: MCPServerType
    public let command: String?
    public let args: [String]?
    public let env: [String: String]?
    public let cwd: String?
    public let url: String?
    public let headers: [String: String]?
    public let allowedTools: [String]?
    public let timeout: Double?

    public init(
        type: MCPServerType,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil,
        url: String? = nil,
        headers: [String: String]? = nil,
        allowedTools: [String]? = nil,
        timeout: Double? = nil
    ) {
        self.type = type
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
        self.allowedTools = allowedTools
        self.timeout = timeout
    }

    public func isToolAllowed(_ toolName: String) -> Bool {
        guard let allowedTools else { return false }
        return allowedTools.contains("*") || allowedTools.contains(toolName)
    }
}

public enum MCPServerType: String, Codable, Sendable {
    case local
    case stdio
    case http
    case sse
}

public struct ServerConfiguration: Codable, Sendable {
    public let mcpServers: [String: MCPServerConfiguration]
    public let allowedCliTools: [String]
    public let bodyLimitMiB: Int
    public let excludedFilePatterns: [String]
    public let reasoningEffort: ReasoningEffort?
    public let autoApprovePermissions: AutoApprovePermissions

    public init(
        mcpServers: [String: MCPServerConfiguration] = [:],
        allowedCliTools: [String] = [],
        bodyLimitMiB: Int = 4,
        excludedFilePatterns: [String] = [],
        reasoningEffort: ReasoningEffort? = .xhigh,
        autoApprovePermissions: AutoApprovePermissions = .kinds([.read, .mcp])
    ) {
        self.mcpServers = mcpServers
        self.allowedCliTools = allowedCliTools
        self.bodyLimitMiB = bodyLimitMiB
        self.excludedFilePatterns = excludedFilePatterns
        self.reasoningEffort = reasoningEffort
        self.autoApprovePermissions = autoApprovePermissions
    }

    public var bodyLimitBytes: Int {
        bodyLimitMiB * 1024 * 1024
    }

    public var hasLocalMCPServers: Bool {
        mcpServers.values.contains { $0.type == .local || $0.type == .stdio }
    }

    public func isCliToolAllowed(_ toolName: String) -> Bool {
        allowedCliTools.contains("*") || allowedCliTools.contains(toolName)
    }

    public func isMCPToolAllowed(_ toolName: String) -> Bool {
        mcpServers.values.contains { $0.isToolAllowed(toolName) }
    }

    public static let `default` = ServerConfiguration()
}