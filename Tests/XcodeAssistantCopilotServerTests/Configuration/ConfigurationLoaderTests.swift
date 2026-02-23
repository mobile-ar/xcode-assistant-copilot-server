import Testing
import Foundation
@testable import XcodeAssistantCopilotServer

@Test func loadReturnsDefaultConfigWhenPathIsNil() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let config = try loader.load(from: nil)
    #expect(config.mcpServers.isEmpty)
    #expect(config.allowedCliTools.isEmpty)
    #expect(config.bodyLimitMiB == 4)
    #expect(config.excludedFilePatterns.isEmpty)
    #expect(config.reasoningEffort == .xhigh)
    #expect(logger.infoMessages.contains(where: { $0.contains("defaults") }))
}

@Test func loadReturnsDefaultConfigWhenFileDoesNotExist() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let config = try loader.load(from: "/nonexistent/path/config.json")
    #expect(config.mcpServers.isEmpty)
    #expect(config.allowedCliTools.isEmpty)
    #expect(config.bodyLimitMiB == 4)
    #expect(logger.warnMessages.contains(where: { $0.contains("nonexistent") }))
}

@Test func loadParsesValidJSONConfig() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 8,
        "excludedFilePatterns": ["mock", "generated"],
        "reasoningEffort": "high",
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_config_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.bodyLimitMiB == 8)
    #expect(config.excludedFilePatterns == ["mock", "generated"])
    #expect(config.reasoningEffort == .high)
    #expect(config.autoApprovePermissions.isApproved(.read) == true)
    #expect(config.autoApprovePermissions.isApproved(.write) == true)
}

@Test func loadParsesConfigWithMCPServer() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "xcode": {
                "type": "local",
                "command": "xcrun",
                "args": ["mcpbridge"],
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": ["read", "mcp"]
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_mcp_config_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.mcpServers.count == 1)
    #expect(config.mcpServers["xcode"] != nil)
    #expect(config.mcpServers["xcode"]?.type == .local)
    #expect(config.mcpServers["xcode"]?.command == "xcrun")
    #expect(config.mcpServers["xcode"]?.args == ["mcpbridge"])
    #expect(config.mcpServers["xcode"]?.isToolAllowed("any_tool") == true)
}

@Test func loadParsesConfigWithPermissionKinds() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": ["read", "mcp"]
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_perms_config_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.autoApprovePermissions.isApproved(.read) == true)
    #expect(config.autoApprovePermissions.isApproved(.mcp) == true)
    #expect(config.autoApprovePermissions.isApproved(.write) == false)
    #expect(config.autoApprovePermissions.isApproved(.shell) == false)
    #expect(config.autoApprovePermissions.isApproved(.url) == false)
}

@Test func loadParsesConfigWithAllPermissionsDenied() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": false
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_deny_config_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.autoApprovePermissions.isApproved(.read) == false)
    #expect(config.autoApprovePermissions.isApproved(.write) == false)
    #expect(config.autoApprovePermissions.isApproved(.mcp) == false)
}

@Test func loadThrowsOnInvalidJSON() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_invalid_\(UUID().uuidString).json")
    try? "not valid json {{{{".write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadThrowsOnBodyLimitTooLow() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 0,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_low_body_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadThrowsOnBodyLimitTooHigh() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 200,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_high_body_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadThrowsOnWildcardMixedWithOtherCliTools() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": ["*", "grep"],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_wildcard_mix_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadAcceptsWildcardAloneInCliTools() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": ["*"],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_wildcard_ok_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.allowedCliTools == ["*"])
    #expect(config.isCliToolAllowed("anything") == true)
}

@Test func loadThrowsOnLocalMCPServerMissingCommand() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "broken": {
                "type": "local",
                "args": ["arg1"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_no_cmd_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadThrowsOnLocalMCPServerWithEmptyCommand() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "broken": {
                "type": "local",
                "command": "",
                "args": []
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_empty_cmd_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadThrowsOnHTTPMCPServerMissingURL() {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "remote": {
                "type": "http"
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_no_url_\(UUID().uuidString).json")
    try? json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    #expect(throws: ConfigurationLoaderError.self) {
        try loader.load(from: configPath.path)
    }
}

@Test func loadResolvesRelativePathsInMCPServerArgs() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "xcode": {
                "type": "local",
                "command": "node",
                "args": ["./scripts/proxy.mjs", "--flag"],
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_resolve_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    let args = config.mcpServers["xcode"]?.args
    #expect(args != nil)
    #expect(args?.first?.hasPrefix("./") == false)
    #expect(args?.first?.contains("scripts/proxy.mjs") == true)
    #expect(args?[1] == "--flag")
}

@Test func loadDoesNotResolveAbsolutePathsInMCPServerArgs() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "xcode": {
                "type": "local",
                "command": "node",
                "args": ["/absolute/path/script.mjs"],
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_abs_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    let args = config.mcpServers["xcode"]?.args
    #expect(args?.first == "/absolute/path/script.mjs")
}

@Test func loadParsesAllReasoningEffortValues() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let efforts: [(String, ReasoningEffort)] = [
        ("low", .low),
        ("medium", .medium),
        ("high", .high),
        ("xhigh", .xhigh),
    ]

    for (raw, expected) in efforts {
        let json = """
        {
            "mcpServers": {},
            "allowedCliTools": [],
            "bodyLimitMiB": 4,
            "excludedFilePatterns": [],
            "reasoningEffort": "\(raw)",
            "autoApprovePermissions": true
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test_effort_\(raw)_\(UUID().uuidString).json")
        try json.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let config = try loader.load(from: configPath.path)
        #expect(config.reasoningEffort == expected)
    }
}

@Test func loadParsesConfigWithoutReasoningEffort() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_no_effort_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.reasoningEffort == nil)
}

@Test func loadLogsConfigSummary() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "xcode": {
                "type": "local",
                "command": "xcrun",
                "args": ["mcpbridge"],
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": ["grep", "glob"],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "reasoningEffort": "high",
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_summary_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let _ = try loader.load(from: configPath.path)
    #expect(logger.infoMessages.contains(where: { $0.contains("1 MCP server(s)") }))
    #expect(logger.infoMessages.contains(where: { $0.contains("2 allowed CLI tool(s)") }))
    #expect(logger.infoMessages.contains(where: { $0.contains("Reasoning effort: high") }))
}

@Test func loadLogsAllCliToolsAllowedSummary() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": ["*"],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_all_cli_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let _ = try loader.load(from: configPath.path)
    #expect(logger.infoMessages.contains(where: { $0.contains("all CLI tools allowed") }))
}

@Test func configurationLoaderErrorDescriptions() {
    let notFound = ConfigurationLoaderError.fileNotFound("/path/to/config.json")
    #expect(notFound.description.contains("/path/to/config.json"))
    #expect(notFound.description.contains("not found"))

    let invalidJSON = ConfigurationLoaderError.invalidJSON("unexpected token")
    #expect(invalidJSON.description.contains("unexpected token"))
    #expect(invalidJSON.description.contains("parse"))

    let validation = ConfigurationLoaderError.validationFailed("bodyLimitMiB must be positive")
    #expect(validation.description.contains("bodyLimitMiB must be positive"))
    #expect(validation.description.contains("validation"))
}

@Test func configurationLoaderErrorFileNotFoundDescription() {
    let error = ConfigurationLoaderError.fileNotFound("/missing/config.json")
    #expect(error.description == "Configuration file not found: /missing/config.json")
}

@Test func configurationLoaderErrorInvalidJSONDescription() {
    let error = ConfigurationLoaderError.invalidJSON("Unexpected character at line 5")
    #expect(error.description == "Failed to parse configuration JSON: Unexpected character at line 5")
}

@Test func configurationLoaderErrorValidationFailedDescription() {
    let error = ConfigurationLoaderError.validationFailed("bodyLimitMiB out of range")
    #expect(error.description == "Configuration validation failed: bodyLimitMiB out of range")
}

@Test func loadParsesConfigWithMultipleMCPServers() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "xcode": {
                "type": "local",
                "command": "xcrun",
                "args": ["mcpbridge"],
                "allowedTools": ["*"]
            },
            "custom": {
                "type": "stdio",
                "command": "/usr/local/bin/mcp-server",
                "args": ["--verbose"],
                "allowedTools": ["search", "read"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_multi_mcp_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.mcpServers.count == 2)
    #expect(config.mcpServers["xcode"]?.type == .local)
    #expect(config.mcpServers["custom"]?.type == .stdio)
    #expect(config.mcpServers["custom"]?.isToolAllowed("search") == true)
    #expect(config.mcpServers["custom"]?.isToolAllowed("delete") == false)
}

@Test func loadParsesConfigWithSSEMCPServer() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "remote": {
                "type": "sse",
                "url": "https://example.com/mcp",
                "headers": {"Authorization": "Bearer token123"},
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_sse_mcp_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    #expect(config.mcpServers["remote"]?.type == .sse)
    #expect(config.mcpServers["remote"]?.url == "https://example.com/mcp")
    #expect(config.mcpServers["remote"]?.headers?["Authorization"] == "Bearer token123")
}

@Test func defaultConfigurationHasExpectedValues() {
    let config = ServerConfiguration.shared
    #expect(config.mcpServers.isEmpty)
    #expect(config.allowedCliTools.isEmpty)
    #expect(config.bodyLimitMiB == 4)
    #expect(config.bodyLimitBytes == 4 * 1024 * 1024)
    #expect(config.excludedFilePatterns.isEmpty)
    #expect(config.reasoningEffort == .xhigh)
    #expect(config.autoApprovePermissions.isApproved(.read) == true)
    #expect(config.autoApprovePermissions.isApproved(.mcp) == true)
    #expect(config.autoApprovePermissions.isApproved(.write) == false)
    #expect(config.hasLocalMCPServers == false)
}

@Test func serverConfigurationBodyLimitBytesCalculation() {
    let config = ServerConfiguration(bodyLimitMiB: 10)
    #expect(config.bodyLimitBytes == 10 * 1024 * 1024)
}

@Test func serverConfigurationHasLocalMCPServers() {
    let withLocal = ServerConfiguration(
        mcpServers: [
            "xcode": MCPServerConfiguration(type: .local, command: "xcrun", args: ["mcpbridge"]),
        ]
    )
    #expect(withLocal.hasLocalMCPServers == true)

    let withStdio = ServerConfiguration(
        mcpServers: [
            "custom": MCPServerConfiguration(type: .stdio, command: "/bin/tool"),
        ]
    )
    #expect(withStdio.hasLocalMCPServers == true)

    let withHTTP = ServerConfiguration(
        mcpServers: [
            "remote": MCPServerConfiguration(type: .http, url: "https://example.com"),
        ]
    )
    #expect(withHTTP.hasLocalMCPServers == false)

    let empty = ServerConfiguration()
    #expect(empty.hasLocalMCPServers == false)
}

@Test func serverConfigurationIsCliToolAllowed() {
    let config = ServerConfiguration(allowedCliTools: ["grep", "glob"])
    #expect(config.isCliToolAllowed("grep") == true)
    #expect(config.isCliToolAllowed("glob") == true)
    #expect(config.isCliToolAllowed("bash") == false)

    let wildcard = ServerConfiguration(allowedCliTools: ["*"])
    #expect(wildcard.isCliToolAllowed("anything") == true)
}

@Test func serverConfigurationIsMCPToolAllowed() {
    let config = ServerConfiguration(
        mcpServers: [
            "server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search", "read"]),
            "server2": MCPServerConfiguration(type: .local, command: "cmd2", allowedTools: ["*"]),
        ]
    )
    #expect(config.isMCPToolAllowed("search") == true)
    #expect(config.isMCPToolAllowed("read") == true)
    #expect(config.isMCPToolAllowed("anything") == true)

    let restricted = ServerConfiguration(
        mcpServers: [
            "server": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["only_this"]),
        ]
    )
    #expect(restricted.isMCPToolAllowed("only_this") == true)
    #expect(restricted.isMCPToolAllowed("other") == false)
}

@Test func mcpServerConfigurationIsToolAllowed() {
    let wildcard = MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])
    #expect(wildcard.isToolAllowed("anything") == true)

    let specific = MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])
    #expect(specific.isToolAllowed("search") == true)
    #expect(specific.isToolAllowed("write") == false)

    let none = MCPServerConfiguration(type: .local, command: "cmd", allowedTools: nil)
    #expect(none.isToolAllowed("anything") == false)

    let empty = MCPServerConfiguration(type: .local, command: "cmd", allowedTools: [])
    #expect(empty.isToolAllowed("anything") == false)
}

@Test func autoApprovePermissionsAllTrue() {
    let perms = AutoApprovePermissions.all(true)
    #expect(perms.isApproved(.read) == true)
    #expect(perms.isApproved(.write) == true)
    #expect(perms.isApproved(.shell) == true)
    #expect(perms.isApproved(.mcp) == true)
    #expect(perms.isApproved(.url) == true)
}

@Test func autoApprovePermissionsAllFalse() {
    let perms = AutoApprovePermissions.all(false)
    #expect(perms.isApproved(.read) == false)
    #expect(perms.isApproved(.write) == false)
    #expect(perms.isApproved(.shell) == false)
    #expect(perms.isApproved(.mcp) == false)
    #expect(perms.isApproved(.url) == false)
}

@Test func autoApprovePermissionsKinds() {
    let perms = AutoApprovePermissions.kinds([.read, .shell])
    #expect(perms.isApproved(.read) == true)
    #expect(perms.isApproved(.shell) == true)
    #expect(perms.isApproved(.write) == false)
    #expect(perms.isApproved(.mcp) == false)
    #expect(perms.isApproved(.url) == false)
}

@Test func loadHandlesRelativePath() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    // A relative path that doesn't exist should return defaults
    let config = try loader.load(from: "nonexistent_relative_config.json")
    #expect(config.mcpServers.isEmpty)
    #expect(config.bodyLimitMiB == 4)
}

@Test func loadParsesConfigWithEnvironmentInMCPServer() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    let json = """
    {
        "mcpServers": {
            "custom": {
                "type": "local",
                "command": "/usr/bin/env",
                "args": ["my-tool"],
                "env": {
                    "MY_VAR": "value1",
                    "ANOTHER_VAR": "value2"
                },
                "cwd": "/tmp",
                "timeout": 30.0,
                "allowedTools": ["*"]
            }
        },
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let configPath = tempDir.appendingPathComponent("test_env_\(UUID().uuidString).json")
    try json.write(to: configPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: configPath) }

    let config = try loader.load(from: configPath.path)
    let server = config.mcpServers["custom"]
    #expect(server?.env?["MY_VAR"] == "value1")
    #expect(server?.env?["ANOTHER_VAR"] == "value2")
    #expect(server?.cwd == "/tmp")
    #expect(server?.timeout == 30.0)
}

@Test func loadParsesBodyLimitBoundaryValues() throws {
    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)

    // bodyLimitMiB == 1 is valid
    let json1 = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 1,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let tempDir = FileManager.default.temporaryDirectory
    let path1 = tempDir.appendingPathComponent("test_body_1_\(UUID().uuidString).json")
    try json1.write(to: path1, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path1) }

    let config1 = try loader.load(from: path1.path)
    #expect(config1.bodyLimitMiB == 1)
    #expect(config1.bodyLimitBytes == 1 * 1024 * 1024)

    // bodyLimitMiB == 100 is valid
    let json100 = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 100,
        "excludedFilePatterns": [],
        "autoApprovePermissions": true
    }
    """

    let path100 = tempDir.appendingPathComponent("test_body_100_\(UUID().uuidString).json")
    try json100.write(to: path100, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path100) }

    let config100 = try loader.load(from: path100.path)
    #expect(config100.bodyLimitMiB == 100)
    #expect(config100.bodyLimitBytes == 100 * 1024 * 1024)
}
