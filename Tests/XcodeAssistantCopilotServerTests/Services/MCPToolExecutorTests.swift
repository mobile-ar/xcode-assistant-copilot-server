@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

private func makeToolCall(
    name: String,
    id: String? = nil,
    arguments: String = "{}"
) -> ToolCall {
    ToolCall(
        index: 0,
        id: id ?? "call_\(name)",
        type: "function",
        function: ToolCallFunction(name: name, arguments: arguments)
    )
}

private func makeExecutor(
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    configurationStore: ConfigurationStore = ConfigurationStore(initial: ServerConfiguration()),
    logger: LoggerProtocol = MockLogger()
) -> MCPToolExecutor {
    MCPToolExecutor(
        bridgeHolder: bridgeHolder,
        configurationStore: configurationStore,
        logger: logger
    )
}

@Suite("MCPToolExecutor")
struct MCPToolExecutorTests {

    @Test func returnsBridgeNotAvailableWhenNoBridge() async throws {
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder())
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("MCP bridge not available"))
    }

    @Test func blockedWhenMCPPermissionNotApproved() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.tools = [MCPTool(name: "search")]
        mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

        let logger = MockLogger()
        let config = ServerConfiguration(
            mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
            autoApprovePermissions: .kinds([.read])
        )
        let executor = makeExecutor(
            bridgeHolder: MCPBridgeHolder(mcpBridge),
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("MCP tool execution is not approved"))
        #expect(result.contains("autoApprovePermissions"))
        #expect(mcpBridge.calledTools.isEmpty)
        #expect(logger.warnMessages.contains { $0.contains("not approved") })
    }

    @Test func blockedWhenAllPermissionsFalse() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.tools = [MCPTool(name: "read_file")]
        mcpBridge.callResults = ["read_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "content")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
            autoApprovePermissions: .all(false)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "read_file")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("not approved"))
        #expect(mcpBridge.calledTools.isEmpty)
    }

    @Test func blockedWhenToolNotInAllowList() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.tools = [MCPTool(name: "delete_file")]
        mcpBridge.callResults = ["delete_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "deleted")])]

        let logger = MockLogger()
        let config = ServerConfiguration(
            mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search", "read"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let executor = makeExecutor(
            bridgeHolder: MCPBridgeHolder(mcpBridge),
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let toolCall = makeToolCall(name: "delete_file")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("not allowed by server configuration"))
        #expect(result.contains("delete_file"))
        #expect(mcpBridge.calledTools.isEmpty)
        #expect(logger.warnMessages.contains { $0.contains("not in the allowed tools list") })
    }

    @Test func blockedWhenNoMCPServersConfigured() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

        let config = ServerConfiguration(
            mcpServers: [:],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("not allowed by server configuration"))
        #expect(mcpBridge.calledTools.isEmpty)
    }

    @Test func allowedWhenPermissionAndAllowListPass() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found it")])]

        let config = ServerConfiguration(
            mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result == "found it")
        #expect(mcpBridge.calledTools.count == 1)
        #expect(mcpBridge.calledTools[0].name == "search")
    }

    @Test func allowedWhenAllPermissionsTrue() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result == "result")
    }

    @Test func allowedWithWildcardInAllowedTools() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["any_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "wildcard ok")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "any_tool")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result == "wildcard ok")
    }

    @Test func returnsErrorWhenBridgeCallFails() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callToolError = MCPBridgeError.toolExecutionFailed("connection lost")

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("Error executing tool"))
        #expect(mcpBridge.calledTools.count == 1)
    }

    @Test func timesOutUsingConfiguredServerTimeout() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callToolDelay = .seconds(5)
        mcpBridge.callResults = ["slow": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "done")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["slow"], timeoutSeconds: 0.05)],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "slow")

        let result = try await executor.execute(toolCall: toolCall, serverName: "s")

        #expect(result.contains("timed out"))
    }

    @Test func usesDefaultTimeoutWhenServerTimeoutMissing() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["fast": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "quick")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["fast"])],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "fast")

        let result = try await executor.execute(toolCall: toolCall, serverName: "s")

        #expect(result == "quick")
    }

    @Test func usesDefaultTimeoutWhenServerTimeoutIsInvalid() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["fast": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "quick")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["fast"], timeoutSeconds: -1)],
            autoApprovePermissions: .kinds([.mcp])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "fast")

        let result = try await executor.execute(toolCall: toolCall, serverName: "s")

        #expect(result == "quick")
    }

    @Test func checksPermissionBeforeAllowList() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
            autoApprovePermissions: .kinds([.read])
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "search")

        let result = try await executor.execute(toolCall: toolCall, serverName: "")

        #expect(result.contains("not approved"))
        #expect(!result.contains("not allowed"))
    }

    @Test func retriesWithResolvedTabIdentifierWhenBridgeReturnsTabError() async throws {
        let tabError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/Sumatron2/Sumatron2.xcodeproj
        * tabIdentifier: windowtab2, workspacePath: /Users/dev/Projects/spark-app-ios/Spark.xcworkspace
        """
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.sequentialCallResults["XcodeUpdate"] = [
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: tabError)], isError: false),
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: "File updated successfully")], isError: false),
        ]

        let logger = MockLogger()
        let config = ServerConfiguration(
            mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config), logger: logger)
        let toolCall = makeToolCall(
            name: "XcodeUpdate",
            arguments: #"{"tabIdentifier":"UserSummaryView.swift","filePath":"Sumatron2/Screens/Profile/UserSummaryView.swift","oldString":"old","newString":"new"}"#
        )

        let result = try await executor.execute(toolCall: toolCall, serverName: "xcode")

        #expect(result == "File updated successfully")
        #expect(mcpBridge.calledTools.count == 2)
        #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
        #expect(logger.debugMessages.contains { $0.contains("retrying with resolved") && $0.contains("windowtab1") })
    }

    @Test func retriesAndSelectsCorrectTabByFilePath() async throws {
        let tabError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/Sumatron2/Sumatron2.xcodeproj
        * tabIdentifier: windowtab2, workspacePath: /Users/dev/Projects/spark-app-ios/Spark.xcworkspace
        """
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.sequentialCallResults["XcodeRead"] = [
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: tabError)], isError: false),
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: "file contents")], isError: false),
        ]

        let config = ServerConfiguration(
            mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(
            name: "XcodeRead",
            arguments: #"{"tabIdentifier":"HomeView.swift","filePath":"spark-app-ios/Spark/Views/HomeView.swift"}"#
        )

        let result = try await executor.execute(toolCall: toolCall, serverName: "xcode")

        #expect(result == "file contents")
        #expect(mcpBridge.calledTools.count == 2)
        #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab2")
    }

    @Test func returnsFallbackTabWhenFilePathDoesNotMatchAnyWorkspace() async throws {
        let tabError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/Sumatron2/Sumatron2.xcodeproj
        """
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.sequentialCallResults["XcodeGrep"] = [
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: tabError)], isError: false),
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: "grep results")], isError: false),
        ]

        let config = ServerConfiguration(
            mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(
            name: "XcodeGrep",
            arguments: #"{"tabIdentifier":"someFile.swift","filePath":"OtherProject/SomeFile.swift","pattern":"foo"}"#
        )

        let result = try await executor.execute(toolCall: toolCall, serverName: "xcode")

        #expect(result == "grep results")
        #expect(mcpBridge.calledTools.count == 2)
        #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
    }

    @Test func doesNotRetryWhenErrorTextHasNoWindowEntries() async throws {
        let tabErrorNoWindows = "Error: Valid tabIdentifier required. No windows open."
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callResults = ["XcodeUpdate": MCPToolResult(
            content: [MCPToolResultContent(type: "text", text: tabErrorNoWindows)],
            isError: false
        )]

        let config = ServerConfiguration(
            mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "XcodeUpdate", arguments: #"{"tabIdentifier":"foo","filePath":"Foo/Bar.swift","oldString":"a","newString":"b"}"#)

        let result = try await executor.execute(toolCall: toolCall, serverName: "xcode")

        #expect(result == tabErrorNoWindows)
        #expect(mcpBridge.calledTools.count == 1)
    }

    @Test func usesSourceFilePathWhenFilePathAbsent() async throws {
        let tabError = """
        Error: Valid tabIdentifier required. Choose from the following open windows:
        * tabIdentifier: windowtab1, workspacePath: /Users/dev/Projects/MyApp/MyApp.xcodeproj
        """
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.sequentialCallResults["ExecuteSnippet"] = [
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: tabError)], isError: false),
            MCPToolResult(content: [MCPToolResultContent(type: "text", text: "snippet output")], isError: false),
        ]

        let config = ServerConfiguration(
            mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(
            name: "ExecuteSnippet",
            arguments: #"{"tabIdentifier":"bad","sourceFilePath":"MyApp/Sources/Main.swift","codeSnippet":"print(1)"}"#
        )

        let result = try await executor.execute(toolCall: toolCall, serverName: "xcode")

        #expect(result == "snippet output")
        #expect(mcpBridge.calledTools.count == 2)
        #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
    }

    @Test func throwsCancellationErrorWhenTaskIsCancelled() async throws {
        let mcpBridge = MockMCPBridgeService()
        mcpBridge.callToolDelay = .seconds(60)
        mcpBridge.callResults = ["slow_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "done")])]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
            autoApprovePermissions: .all(true)
        )
        let executor = makeExecutor(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
        let toolCall = makeToolCall(name: "slow_tool")

        let task = Task {
            try await executor.execute(toolCall: toolCall, serverName: "s")
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // expected
        }
    }

    @Test func respectsPerServerTimeout() async throws {
        let xcodeServer = MockMCPBridgeService()
        xcodeServer.callToolDelay = .milliseconds(300)
        xcodeServer.callResults = ["xcode_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

        let zedServer = MockMCPBridgeService()
        zedServer.callToolDelay = .milliseconds(300)
        zedServer.callResults = ["zed_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

        let config = ServerConfiguration(
            mcpServers: [
                "xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["xcode_tool"], timeoutSeconds: 0.05),
                "zed": MCPServerConfiguration(type: .local, command: "zed", allowedTools: ["zed_tool"], timeoutSeconds: 60),
            ],
            autoApprovePermissions: .kinds([.mcp])
        )

        let xcodeExecutor = makeExecutor(
            bridgeHolder: MCPBridgeHolder(xcodeServer),
            configurationStore: ConfigurationStore(initial: config)
        )
        let zedExecutor = makeExecutor(
            bridgeHolder: MCPBridgeHolder(zedServer),
            configurationStore: ConfigurationStore(initial: config)
        )

        let xcodeResult = try await xcodeExecutor.execute(
            toolCall: makeToolCall(name: "xcode_tool"),
            serverName: "xcode"
        )
        let zedResult = try await zedExecutor.execute(
            toolCall: makeToolCall(name: "zed_tool"),
            serverName: "zed"
        )

        #expect(xcodeResult.contains("timed out after 0.05"), "xcode server should use its 0.05s timeout")
        #expect(zedResult == "result", "zed server should use its 60s timeout and succeed")
    }
}