import Foundation

public struct TimeoutsConfiguration: Codable, Sendable {
    public let requestTimeoutSeconds: UInt64
    public let streamingEndpointTimeoutSeconds: TimeInterval
    public let httpClientTimeoutSeconds: TimeInterval

    public init(
        requestTimeoutSeconds: UInt64 = 300,
        streamingEndpointTimeoutSeconds: TimeInterval = 300,
        httpClientTimeoutSeconds: TimeInterval = 300
    ) {
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.streamingEndpointTimeoutSeconds = streamingEndpointTimeoutSeconds
        self.httpClientTimeoutSeconds = httpClientTimeoutSeconds
    }
}

public enum ReasoningEffort: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high
    case xhigh

    private var ordinal: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .xhigh: 3
        }
    }

    public static func < (lhs: ReasoningEffort, rhs: ReasoningEffort) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    var nextLower: ReasoningEffort? {
        switch self {
        case .low: nil
        case .medium: .low
        case .high: .medium
        case .xhigh: .high
        }
    }
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
    public let timeoutSeconds: Double?

    public init(
        type: MCPServerType,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil,
        url: String? = nil,
        headers: [String: String]? = nil,
        allowedTools: [String]? = nil,
        timeoutSeconds: Double? = nil
    ) {
        self.type = type
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
        self.allowedTools = allowedTools
        self.timeoutSeconds = timeoutSeconds
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
    public let timeouts: TimeoutsConfiguration
    public let maxAgentLoopIterations: Int
    public let contextRecencyWindow: Int
    public let modelsCacheTTLSeconds: TimeInterval

    public init(
        mcpServers: [String: MCPServerConfiguration] = [:],
        allowedCliTools: [String] = [],
        bodyLimitMiB: Int = 4,
        excludedFilePatterns: [String] = [],
        reasoningEffort: ReasoningEffort? = .xhigh,
        autoApprovePermissions: AutoApprovePermissions = .kinds([.read, .mcp]),
        timeouts: TimeoutsConfiguration = TimeoutsConfiguration(),
        maxAgentLoopIterations: Int = 20,
        contextRecencyWindow: Int = 3,
        modelsCacheTTLSeconds: TimeInterval = 600
    ) {
        self.mcpServers = mcpServers
        self.allowedCliTools = allowedCliTools
        self.bodyLimitMiB = bodyLimitMiB
        self.excludedFilePatterns = excludedFilePatterns
        self.reasoningEffort = reasoningEffort
        self.autoApprovePermissions = autoApprovePermissions
        self.timeouts = timeouts
        self.maxAgentLoopIterations = maxAgentLoopIterations
        self.contextRecencyWindow = contextRecencyWindow
        self.modelsCacheTTLSeconds = modelsCacheTTLSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mcpServers = try container.decode([String: MCPServerConfiguration].self, forKey: .mcpServers)
        allowedCliTools = try container.decode([String].self, forKey: .allowedCliTools)
        bodyLimitMiB = try container.decode(Int.self, forKey: .bodyLimitMiB)
        excludedFilePatterns = try container.decode([String].self, forKey: .excludedFilePatterns)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        autoApprovePermissions = try container.decode(AutoApprovePermissions.self, forKey: .autoApprovePermissions)
        timeouts = try container.decodeIfPresent(TimeoutsConfiguration.self, forKey: .timeouts) ?? TimeoutsConfiguration()
        maxAgentLoopIterations = try container.decodeIfPresent(Int.self, forKey: .maxAgentLoopIterations) ?? 20
        contextRecencyWindow = try container.decodeIfPresent(Int.self, forKey: .contextRecencyWindow) ?? 3
        modelsCacheTTLSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .modelsCacheTTLSeconds) ?? 600
    }

    public var bodyLimitBytes: Int {
        bodyLimitMiB * 1024 * 1024
    }

    public var hasLocalMCPServers: Bool {
        mcpServers.values.contains { $0.type == .local || $0.type == .stdio }
    }

    public var localMCPServers: [String: MCPServerConfiguration] {
        mcpServers.filter { $0.value.type == .local || $0.value.type == .stdio }
    }

    public var httpMCPServers: [String: MCPServerConfiguration] {
        mcpServers.filter { $0.value.type == .http }
    }

    public var sseMCPServers: [String: MCPServerConfiguration] {
        mcpServers.filter { $0.value.type == .sse }
    }

    public var hasMCPServers: Bool {
        !mcpServers.isEmpty
    }

    public func isCliToolAllowed(_ toolName: String) -> Bool {
        allowedCliTools.contains("*") || allowedCliTools.contains(toolName)
    }

    public func isMCPToolAllowed(_ toolName: String) -> Bool {
        mcpServers.values.contains { $0.isToolAllowed(toolName) }
    }

    public static let shared = ServerConfiguration()
}
