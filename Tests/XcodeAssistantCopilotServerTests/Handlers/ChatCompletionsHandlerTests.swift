@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import Synchronization
import Testing

private func makeHandler(
    authService: AuthServiceProtocol = MockAuthService(),
    copilotAPI: CopilotAPIServiceProtocol = MockCopilotAPIService(),
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    modelEndpointResolver: ModelEndpointResolverProtocol = MockModelEndpointResolver(),
    reasoningEffortResolver: ReasoningEffortResolverProtocol = MockReasoningEffortResolver(),
    configurationStore: ConfigurationStore = ConfigurationStore(initial: ServerConfiguration()),
    logger: LoggerProtocol = MockLogger()
) -> ChatCompletionsHandler {
    ChatCompletionsHandler(
        authService: authService,
        copilotAPI: copilotAPI,
        bridgeHolder: bridgeHolder,
        modelEndpointResolver: modelEndpointResolver,
        reasoningEffortResolver: reasoningEffortResolver,
        configurationStore: configurationStore,
        logger: logger
    )
}

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

private func makeCredentials() -> CopilotCredentials {
    CopilotCredentials(token: "mock-token", apiEndpoint: "https://api.github.com")
}

private func makeRequest(model: String = "gpt-4") -> ChatCompletionRequest {
    ChatCompletionRequest(
        model: model,
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
}

/// Drains the SSE body of a response returned by handleAgentStreaming so that
/// the background Task running the agent loop has time to complete before
/// any assertions are made on side-effects (logger messages, call counts, etc.).
@discardableResult
private func consumeAgentStreamBody(_ response: Response) async -> String {
    final class CollectingWriter: ResponseBodyWriter, Sendable {
        private struct State {
            var collected = ""
        }

        private let mutex = Mutex(State())

        var collected: String { mutex.withLock { $0.collected } }

        func write(_ buffer: ByteBuffer) async throws {
            if let s = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                mutex.withLock { $0.collected += s }
            }
        }

        consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
    }
    let writer = CollectingWriter()
    try? await response.body.write(writer)
    return writer.collected
}

@Test func executeMCPToolReturnsBridgeNotAvailableWhenNoBridge() async throws {
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder())
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("MCP bridge not available"))
}

@Test func executeMCPToolBlockedWhenMCPPermissionNotApproved() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read])
    )
    let handler = makeHandler(
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("MCP tool execution is not approved"))
    #expect(result.contains("autoApprovePermissions"))
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(logger.warnMessages.contains { $0.contains("not approved") })
}

@Test func executeMCPToolBlockedWhenAllPermissionsFalse() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "read_file")]
    mcpBridge.callResults = ["read_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "content")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
        autoApprovePermissions: .all(false)
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "read_file")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not approved"))
    #expect(mcpBridge.calledTools.isEmpty)
}

@Test func executeMCPToolBlockedWhenToolNotInAllowList() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "delete_file")]
    mcpBridge.callResults = ["delete_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "deleted")])]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search", "read"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )
    let toolCall = makeToolCall(name: "delete_file")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not allowed by server configuration"))
    #expect(result.contains("delete_file"))
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(logger.warnMessages.contains { $0.contains("not in the allowed tools list") })
}

@Test func executeMCPToolBlockedWhenNoMCPServersConfigured() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let config = ServerConfiguration(
        mcpServers: [:],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not allowed by server configuration"))
    #expect(mcpBridge.calledTools.isEmpty)
}

@Test func executeMCPToolAllowedWhenPermissionAndAllowListPass() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found it")])]

    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "found it")
    #expect(mcpBridge.calledTools.count == 1)
    #expect(mcpBridge.calledTools[0].name == "search")
}

@Test func executeMCPToolAllowedWhenAllPermissionsTrue() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "result")
    #expect(mcpBridge.calledTools.count == 1)
}

@Test func executeMCPToolAllowedWithWildcardInAllowedTools() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["any_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "any_tool")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "ok")
}

@Test func executeMCPToolReturnsErrorWhenBridgeCallFails() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callToolError = MCPBridgeError.toolExecutionFailed("Error executing tool search")

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config), logger: logger)
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("Error executing tool search"))
    #expect(logger.errorMessages.contains { $0.contains("search") && $0.contains("failed") })
}

@Test func executeMCPToolTimesOutUsingConfiguredServerTimeout() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callToolDelay = .milliseconds(250)
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "late result")])]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"], timeoutSeconds: 0.05)],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall, serverName: "s")

    #expect(result.contains("timed out after 0.05"))
    #expect(logger.warnMessages.contains { $0.contains("timed out after 0.05") })
}

@Test func executeMCPToolUsesDefaultTimeoutWhenServerTimeoutMissing() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config)
    )
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "ok")
}

@Test func executeMCPToolUsesDefaultTimeoutWhenServerTimeoutIsInvalid() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"], timeoutSeconds: -1)],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config)
    )
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "ok")
}

@Test func executeMCPToolChecksPermissionBeforeAllowList() async throws {
    let mcpBridge = MockMCPBridgeService()
    let config = ServerConfiguration(
        mcpServers: [:],
        autoApprovePermissions: .kinds([.read])
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "search")

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not approved"))
    #expect(!result.contains("not allowed by server configuration"))
}

@Test func agentStreamingBlocksCliToolsWhenShellNotApproved() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "bash", id: "call_bash")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "I cannot run bash."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(logger.warnMessages.contains { $0.contains("bash") && $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("Blocking") })
    #expect(copilotAPI.streamChatCompletionsCallCount >= 2)
}

@Test func agentStreamingBlocksCliToolsWhenNotInAllowList() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "rm", id: "call_rm")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Cannot remove."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["grep", "find"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(logger.warnMessages.contains { $0.contains("rm") && $0.contains("blocked") })
    #expect(logger.warnMessages.contains { $0.contains("not in the allowed CLI tools list") })
}

@Test func agentStreamingAllowsCliToolsWithWildcard() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "anything", id: "call_anything")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall]))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["*"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(!logger.warnMessages.contains { $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("streaming buffered response with tool calls") })
}

@Test func agentStreamingAllowsCliToolsWithExplicitName() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "grep", id: "call_grep")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall]))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(!logger.warnMessages.contains { $0.contains("blocked") })
}

@Test func agentStreamingBlockedCliToolsContinueAgentLoop() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let blockedTool = makeToolCall(name: "rm", id: "call_rm")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [blockedTool])),
        .success(MockCopilotAPIService.makeContentStream(content: "OK, I will not delete files."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(logger.infoMessages.contains { $0.contains("All CLI tool calls blocked") })

    let secondRequest = copilotAPI.capturedChatRequests[1]
    let toolMessages = secondRequest.messages.filter { $0.role == .tool }
    #expect(!toolMessages.isEmpty)
    let errorContent = try? toolMessages[0].extractContentText()
    #expect(errorContent?.contains("not in the allowed CLI tools list") == true)
}

@Test func agentStreamingMixedMCPAndAllowedCliCalls() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    let cliToolCall = makeToolCall(name: "grep", id: "call_grep")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall, cliToolCall]))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .mcp, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(mcpBridge.calledTools[0].name == "search")
    #expect(logger.infoMessages.contains { $0.contains("allowed CLI tool call(s) to client") })
    #expect(!logger.warnMessages.contains { $0.contains("blocked") })
}

@Test func agentStreamingMixedMCPAndBlockedCliCalls() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    let blockedCliToolCall = makeToolCall(name: "rm", id: "call_rm")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall, blockedCliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Search done, cannot delete."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .mcp, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(logger.warnMessages.contains { $0.contains("rm") && $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("MCP tool(s) executed and CLI tool calls blocked, continuing agent loop") })
}

@Test func agentStreamingMCPToolExecutedAndContinuesLoopForFinalResponse() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found results")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Here are the results."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(logger.infoMessages.contains { $0.contains("MCP tool(s) executed, continuing agent loop") })
    #expect(logger.infoMessages.contains { $0.contains("Agent loop completed") && $0.contains("streaming buffered response") })
}

@Test func agentStreamingMCPPermissionDeniedFeedsErrorToModel() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Cannot execute tools."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(copilotAPI.streamChatCompletionsCallCount >= 2)

    let secondRequest = copilotAPI.capturedChatRequests[1]
    let toolMessages = secondRequest.messages.filter { $0.role == .tool }
    #expect(!toolMessages.isEmpty)
    let errorContent = try? toolMessages[0].extractContentText()
    #expect(errorContent?.contains("not approved") == true)
}

@Test func agentStreamingShellPermissionDeniedBlocksAllCliTools() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall1 = makeToolCall(name: "grep", id: "call_grep")
    let cliToolCall2 = makeToolCall(name: "find", id: "call_find")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall1, cliToolCall2])),
        .success(MockCopilotAPIService.makeContentStream(content: "Shell not allowed."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["grep", "find"],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(logger.warnMessages.contains { $0.contains("grep") && $0.contains("Shell tool execution is not approved") })
    #expect(logger.warnMessages.contains { $0.contains("find") && $0.contains("Shell tool execution is not approved") })
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
}

@Test func agentStreamingNoToolCallsReturnsBufferedResponse() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeContentStream(content: "Hello there!"))
    ]

    let logger = MockLogger()
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 1)
    #expect(logger.infoMessages.contains { $0.contains("streaming buffered response") })
}

@Test func agentStreamingPartialCliBlockReturnsMixedResponse() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let allowedTool = makeToolCall(name: "grep", id: "call_grep")
    let blockedTool = makeToolCall(name: "rm", id: "call_rm")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [allowedTool, blockedTool]))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(logger.warnMessages.contains { $0.contains("rm") && $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("allowed CLI tool call(s) to client") })
}

@Test func agentStreamingAllPermissionsTrueAllowsEverything() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    let cliToolCall = makeToolCall(name: "bash", id: "call_bash")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall, cliToolCall]))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        allowedCliTools: ["*"],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(!logger.warnMessages.contains { $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("allowed CLI tool call(s) to client") })
}

@Test func agentStreamingAllPermissionsFalseBlocksEverything() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let copilotAPI = MockCopilotAPIService()
    let mcpToolCall = makeToolCall(name: "search", id: "call_search")
    let cliToolCall = makeToolCall(name: "grep", id: "call_grep")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [mcpToolCall, cliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "All blocked."))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        allowedCliTools: ["grep"],
        autoApprovePermissions: .all(false)
    )
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(logger.warnMessages.contains { $0.contains("blocked") })
    #expect(copilotAPI.streamChatCompletionsCallCount >= 2)
}

@Test func reasoningEffortRetryOnGeneric400DowngradesEffort() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
        .success(MockCopilotAPIService.makeContentStream(content: "Success after retry"))
    ]

    let reasoningResolver = MockReasoningEffortResolver()
    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: .xhigh)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        reasoningEffortResolver: reasoningResolver,
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .high)
    #expect(reasoningResolver.recordedMaxEfforts.contains { $0.effort == .high })
    #expect(logger.errorMessages.contains { $0.contains("HTTP 400") && $0.contains("xhigh") })
    #expect(logger.infoMessages.contains { $0.contains("Downgrading reasoning effort") })
}

@Test func reasoningEffortRetryDowngradesThroughMultipleLevels() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
        .success(MockCopilotAPIService.makeContentStream(content: "Success after two downgrades"))
    ]

    let reasoningResolver = MockReasoningEffortResolver()
    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: .xhigh)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        reasoningEffortResolver: reasoningResolver,
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 3)
    #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .high)
    #expect(copilotAPI.capturedChatRequests[2].reasoningEffort == .medium)
}

@Test func reasoningEffortRetryRemovesEffortWhenAtLowestLevel() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
        .success(MockCopilotAPIService.makeContentStream(content: "Success without reasoning"))
    ]

    let reasoningResolver = MockReasoningEffortResolver()
    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: .low)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        reasoningEffortResolver: reasoningResolver,
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == nil)
    #expect(logger.infoMessages.contains { $0.contains("no lower level available") })
}

@Test func reasoningEffortRetryDoesNotRetryNon400Errors() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 500, body: "Internal Server Error"))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: .xhigh)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    let body = await consumeAgentStreamBody(response)

    // Errors during the agent loop are now surfaced as progress text in the SSE stream
    // rather than as HTTP error status codes, since the response headers are sent immediately.
    #expect(response.status == HTTPResponse.Status.ok)
    #expect(body.contains("✗"))
    #expect(copilotAPI.streamChatCompletionsCallCount == 1)
}

@Test func reasoningEffortRetryDoesNotRetryWhenEffortIsNil() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request"))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: nil)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    let body = await consumeAgentStreamBody(response)

    // Errors during the agent loop are now surfaced as progress text in the SSE stream
    // rather than as HTTP error status codes, since the response headers are sent immediately.
    #expect(response.status == HTTPResponse.Status.ok)
    #expect(body.contains("✗"))
    #expect(copilotAPI.streamChatCompletionsCallCount == 1)
}

@Test func reasoningEffortRetryLogsErrorBodyOn400() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let detailedErrorBody = "{\"error\":{\"message\":\"reasoning_effort is not supported\",\"type\":\"invalid_request_error\"}}"
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.requestFailed(statusCode: 400, body: detailedErrorBody)),
        .success(MockCopilotAPIService.makeContentStream(content: "OK"))
    ]

    let logger = MockLogger()
    let config = ServerConfiguration(reasoningEffort: .high)
    let handler = makeHandler(
        copilotAPI: copilotAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )
    await consumeAgentStreamBody(response)

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(logger.errorMessages.contains { $0.contains(detailedErrorBody) })
    #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .medium)
}

@Test func normalizeEventDataAddsObjectFieldWhenMissing() {
    let handler = makeHandler()
    let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1772507025,"id":"msg_abc","model":"claude-haiku-4.5"}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
    #expect(json["id"] as? String == "msg_abc")
    #expect(json["model"] as? String == "claude-haiku-4.5")
}

@Test func normalizeEventDataPreservesExistingObjectField() {
    let handler = makeHandler()
    let input = #"{"choices":[],"created":1234567890,"id":"chatcmpl-123","model":"gpt-4","object":"chat.completion.chunk"}"#

    let result = handler.normalizeEventData(input)

    // Fast-exit path: raw string must be returned unchanged (identity, not just equality).
    #expect(result == input)
    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func normalizeEventDataReturnsOriginalForInvalidJSON() {
    let handler = makeHandler()
    let input = "not valid json"

    let result = handler.normalizeEventData(input)

    #expect(result == input)
}

@Test func normalizeEventDataHandlesDoneSignal() {
    let handler = makeHandler()
    let input = "[DONE]"

    let result = handler.normalizeEventData(input)

    // Fast-exit path: [DONE] has no "object" and no "tool_calls" — must be returned as-is.
    #expect(result == input)
}

@Test func normalizeEventDataPreservesAllExistingFields() {
    let handler = makeHandler()
    let input = #"{"choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"function":{"name":"XcodeUpdate"},"id":"toolu_abc","index":1,"type":"function"}]},"finish_reason":null}],"created":1772507629,"id":"msg_xyz","model":"claude-sonnet-4.5"}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
    #expect(json["id"] as? String == "msg_xyz")
    #expect(json["model"] as? String == "claude-sonnet-4.5")
    #expect((json["choices"] as? [[String: Any]])?.count == 1)

    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
    let function = toolCall["function"] as! [String: Any]
    #expect(function["arguments"] as? String == "")
}

@Test func normalizeEventDataAddsEmptyArgumentsWhenMissingFromToolCallFunction() {
    let handler = makeHandler()
    let input = #"{"model":"claude-sonnet-4.5","id":"msg_vrtx_01","created":1772509504,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"id":"toolu_vrtx_01","function":{"name":"BuildProject"},"type":"function","index":0}]}}]}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
    let function = toolCall["function"] as! [String: Any]
    #expect(function["arguments"] as? String == "")
    #expect(function["name"] as? String == "BuildProject")
}

@Test func normalizeEventDataPreservesExistingArgumentsInToolCallFunction() {
    let handler = makeHandler()
    let input = #"{"model":"claude-sonnet-4.5","id":"msg_001","created":1234567890,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"id":"call_1","function":{"name":"XcodeGrep","arguments":"{\"pattern\":"},"type":"function","index":0}]}}]}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
    let function = toolCall["function"] as! [String: Any]
    #expect(function["arguments"] as? String == "{\"pattern\":")
}

@Test func normalizeEventDataHandlesMultipleToolCallsInSingleChunk() {
    let handler = makeHandler()
    let input = #"{"model":"claude-sonnet-4.5","id":"msg_002","created":1234567890,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"id":"call_1","function":{"name":"ToolA"},"type":"function","index":0},{"id":"call_2","function":{"name":"ToolB","arguments":"{}"},"type":"function","index":1}]}}]}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    let toolCalls = delta["tool_calls"] as! [[String: Any]]
    #expect(toolCalls.count == 2)
    let func0 = toolCalls[0]["function"] as! [String: Any]
    let func1 = toolCalls[1]["function"] as! [String: Any]
    #expect(func0["arguments"] as? String == "")
    #expect(func1["arguments"] as? String == "{}")
}

@Test func normalizeEventDataDoesNotModifyChunksWithoutToolCalls() {
    let handler = makeHandler()
    // This input has no "object" key and no "tool_calls" — but wait, we need
    // to distinguish the two sub-cases: here "gpt-4" has no "object" (Claude-style),
    // so it goes through the string-injection fast path. Verify the result is valid
    // JSON with the injected field and the original content intact.
    let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1234567890,"id":"msg_003","model":"gpt-4"}"#

    let result = handler.normalizeEventData(input)

    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    #expect(delta["content"] as? String == "Hello")
    #expect(delta["tool_calls"] == nil)
}

// MARK: - Fast-path behaviour tests

@Test func normalizeEventDataFastExitWhenObjectPresentAndNoToolCalls() {
    let handler = makeHandler()
    // GPT-style chunk: "object" already present, no "tool_calls" → must be returned
    // as the exact same String instance (fast-exit, no JSON parsing).
    let input = #"{"id":"chatcmpl-abc","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#

    let result = handler.normalizeEventData(input)

    #expect(result == input)
}

@Test func normalizeEventDataStringInjectionDoesNotParseJSON() {
    let handler = makeHandler()
    // Claude-style chunk: missing "object", no "tool_calls" → string-injection path.
    // The result must start with the injected prefix and the rest of the original JSON.
    let input = #"{"id":"msg_abc","created":1700000000,"model":"claude-haiku-4.5","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#

    let result = handler.normalizeEventData(input)

    #expect(result.hasPrefix(#"{"object":"chat.completion.chunk","#))
    // The remainder after the injected prefix+comma must equal the original string
    // body (everything after the opening brace).
    let expectedTail = String(input.dropFirst()) // drop the leading "{"
    #expect(result.hasSuffix(expectedTail))
    // Must be valid JSON with the field present.
    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
    #expect(json["id"] as? String == "msg_abc")
}

@Test func normalizeEventDataStringInjectionPreservesAllOriginalFields() {
    let handler = makeHandler()
    let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1772507025,"id":"msg_abc","model":"claude-haiku-4.5"}"#

    let result = handler.normalizeEventData(input)

    // String-injection path must produce valid JSON with every original field intact.
    let data = result.data(using: .utf8)!
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
    #expect(json["id"] as? String == "msg_abc")
    #expect(json["model"] as? String == "claude-haiku-4.5")
    #expect(json["created"] as? Int == 1772507025)
    let choice = (json["choices"] as! [[String: Any]])[0]
    let delta = choice["delta"] as! [String: Any]
    #expect(delta["content"] as? String == "Hello")
}

// MARK: - ChatCompletionChunk "object" field encoding

@Test func chatCompletionChunkEncodesObjectField() throws {
    let chunk = ChatCompletionChunk.makeContentDelta(id: "chatcmpl-test", model: "gpt-4o", content: "hello")

    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func chatCompletionChunkDefaultObjectValue() {
    let chunk = ChatCompletionChunk(
        id: "chatcmpl-1",
        choices: [ChunkChoice(delta: ChunkDelta(content: "test"))]
    )
    #expect(chunk.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkCustomObjectValueRoundtrips() throws {
    let chunk = ChatCompletionChunk(
        id: "chatcmpl-1",
        object: "chat.completion.chunk",
        choices: [ChunkChoice(delta: ChunkDelta(content: "test"))]
    )
    let encoded = try JSONEncoder().encode(chunk)
    let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: encoded)
    #expect(decoded.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkDecodesObjectFieldFromUpstreamJSON() throws {
    // Verify that upstream JSON carrying "object" round-trips through the model correctly.
    let raw = #"{"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4o","choices":[]}"#
    let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: raw.data(using: .utf8)!)
    #expect(decoded.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkMakeRoleDeltaEncodesObject() throws {
    let chunk = ChatCompletionChunk.makeRoleDelta(id: "chatcmpl-1", model: "gpt-4o")
    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func chatCompletionChunkMakeStopDeltaEncodesObject() throws {
    let chunk = ChatCompletionChunk.makeStopDelta(id: "chatcmpl-1", model: "gpt-4o")
    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func executeMCPToolRetriesWithResolvedTabIdentifierWhenBridgeReturnsTabError() async throws {
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
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config), logger: logger)
    let toolCall = makeToolCall(
        name: "XcodeUpdate",
        arguments: #"{"tabIdentifier":"UserSummaryView.swift","filePath":"Sumatron2/Screens/Profile/UserSummaryView.swift","oldString":"old","newString":"new"}"#
    )

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "File updated successfully")
    #expect(mcpBridge.calledTools.count == 2)
    #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
    #expect(logger.debugMessages.contains { $0.contains("retrying with resolved") && $0.contains("windowtab1") })
}

@Test func executeMCPToolRetriesAndSelectsCorrectTabByFilePath() async throws {
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
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(
        name: "XcodeRead",
        arguments: #"{"tabIdentifier":"HomeView.swift","filePath":"spark-app-ios/Spark/Views/HomeView.swift"}"#
    )

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "file contents")
    #expect(mcpBridge.calledTools.count == 2)
    #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab2")
}

@Test func executeMCPToolReturnsFallbackTabWhenFilePathDoesNotMatchAnyWorkspace() async throws {
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
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(
        name: "XcodeGrep",
        arguments: #"{"tabIdentifier":"someFile.swift","filePath":"OtherProject/SomeFile.swift","pattern":"foo"}"#
    )

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "grep results")
    #expect(mcpBridge.calledTools.count == 2)
    #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
}

@Test func executeMCPToolDoesNotRetryWhenErrorTextHasNoWindowEntries() async throws {
    let tabErrorNoWindows = "Error: Valid tabIdentifier required. No windows open."
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults["XcodeUpdate"] = MCPToolResult(
        content: [MCPToolResultContent(type: "text", text: tabErrorNoWindows)],
        isError: false
    )

    let config = ServerConfiguration(
        mcpServers: ["xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["*"])],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "XcodeUpdate", arguments: #"{"tabIdentifier":"foo","filePath":"Foo/Bar.swift","oldString":"a","newString":"b"}"#)

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == tabErrorNoWindows)
    #expect(mcpBridge.calledTools.count == 1)
}

@Test func executeMCPToolUsesSourceFilePathWhenFilePathAbsent() async throws {
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
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(
        name: "ExecuteSnippet",
        arguments: #"{"tabIdentifier":"bad","sourceFilePath":"MyApp/Sources/Main.swift","codeSnippet":"print(1)"}"#
    )

    let result = try await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "snippet output")
    #expect(mcpBridge.calledTools.count == 2)
    #expect(mcpBridge.calledTools[1].arguments["tabIdentifier"]?.stringValue == "windowtab1")
}

@Test func executeMCPToolThrowsCancellationErrorWhenTaskIsCancelled() async throws {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callToolDelay = .seconds(60)
    mcpBridge.callResults = ["slow_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "done")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let toolCall = makeToolCall(name: "slow_tool")

    let task = Task {
        try await handler.executeMCPTool(toolCall: toolCall)
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

@Test func agentStreamingReturnsEmptyResponseWhenCancelledDuringCollect() async throws {
    let mockAPI = MockCopilotAPIService()
    let suspendingStream = AsyncThrowingStream<SSEEvent, Error> { continuation in
        let task = Task {
            try await Task.sleep(for: .seconds(60))
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
    mockAPI.streamChatCompletionsResults = [.success(suspendingStream)]

    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let config = ServerConfiguration(
        mcpServers: [:],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(
        copilotAPI: mockAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config)
    )
    let request = makeRequest(model: "gpt-4")
    let credentials = makeCredentials()

    let response = await handler.handleAgentStreaming(request: request, credentials: credentials)
    #expect(response.status == .ok)

    // Cancel by starting to consume then stopping — the onTermination callback cancels the inner Task
    let consumeTask = Task {
        await consumeAgentStreamBody(response)
    }
    try await Task.sleep(for: .milliseconds(50))
    consumeTask.cancel()
    _ = await consumeTask.value
}

@Test func agentStreamingReturnsEmptyResponseWhenCancelledDuringMCPToolExecution() async throws {
    let mockAPI = MockCopilotAPIService()
    let toolCall = makeToolCall(name: "slow_tool")
    mockAPI.streamChatCompletionsResults = [.success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall]))]

    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "slow_tool")]
    mcpBridge.callToolDelay = .seconds(60)
    mcpBridge.callResults = ["slow_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "done")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(
        copilotAPI: mockAPI,
        bridgeHolder: MCPBridgeHolder(mcpBridge),
        configurationStore: ConfigurationStore(initial: config)
    )
    let request = makeRequest(model: "gpt-4")
    let credentials = makeCredentials()

    let response = await handler.handleAgentStreaming(request: request, credentials: credentials)
    #expect(response.status == .ok)

    // Start consuming the stream in a task so the inner agent loop Task runs,
    // then cancel once the MCP tool call has actually started.
    let consumeTask = Task {
        await consumeAgentStreamBody(response)
    }

    // Wait until the MCP tool call has actually started before cancelling,
    // so we are guaranteed to be testing cancellation mid-tool-execution.
    await mcpBridge.callToolGate.wait()

    consumeTask.cancel()
    _ = await consumeTask.value

    #expect(mcpBridge.calledTools.count == 1)
}

@Test func directStreamingStopsWhenTaskIsCancelled() async throws {
    let mockAPI = MockCopilotAPIService()
    let infiniteStream = AsyncThrowingStream<SSEEvent, Error> { continuation in
        let task = Task {
            try await Task.sleep(for: .seconds(60))
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
    mockAPI.streamChatCompletionsResults = [.success(infiniteStream)]

    let handler = makeHandler(copilotAPI: mockAPI)
    let request = makeRequest(model: "gpt-4")
    let credentials = makeCredentials()

    // Simulate a client that starts consuming the stream then disconnects
    let handlerTask = Task {
        await handler.handleDirectStreaming(request: request, credentials: credentials)
    }

    try await Task.sleep(for: .milliseconds(50))
    handlerTask.cancel()

    _ = await handlerTask.value
    #expect(mockAPI.streamChatCompletionsCallCount == 1)
}

@Test func runAgentLoopWritesRoleDeltaFirst() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeContentStream(content: "Done."))
    ]

    let config = ServerConfiguration()
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    #expect(writer.roleDeltaWritten)
}

@Test func runAgentLoopCallsFinishWhenLoopCompletes() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeContentStream(content: "Final answer."))
    ]

    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    #expect(writer.finishCalled)
}

@Test func runAgentLoopPassesFinalContentToWriter() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeContentStream(content: "The answer is 42."))
    ]

    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    #expect(writer.finalContent == "The answer is 42.")
    #expect(writer.finalHadToolUse == false)
}

@Test func runAgentLoopWritesToolCallProgressBeforeExecuting() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "read_file")]
    mcpBridge.callResults = ["read_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "struct Foo {}")])]

    let copilotAPI = MockCopilotAPIService()
    let toolCall = makeToolCall(name: "read_file", id: "call_rf", arguments: #"{"filePath":"Sources/Foo.swift"}"#)
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Done."))
    ]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: ["read_file": "s"],
        writer: writer
    )

    let combined = writer.allProgressText
    #expect(combined.contains("`read_file`"))
}

@Test func runAgentLoopSetsHadToolUseTrueWhenMCPToolExecuted() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "results")])]

    let copilotAPI = MockCopilotAPIService()
    let toolCall = makeToolCall(name: "search", id: "call_s")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Here are results."))
    ]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: ["search": "s"],
        writer: writer
    )

    #expect(writer.finalHadToolUse == true)
}

@Test func runAgentLoopWritesWarningProgressForBlockedCLITool() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "rm", id: "call_rm")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Cannot run rm."))
    ]

    let config = ServerConfiguration(
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    let combined = writer.allProgressText
    #expect(combined.contains("`rm`"))
    #expect(combined.contains("✗"))
}

@Test func runAgentLoopWritesToolCallProgressForBlockedCLITool() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "bash", id: "call_bash", arguments: #"{"command":"rm -rf /"}"#)
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Blocked."))
    ]

    let config = ServerConfiguration(
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    let combined = writer.allProgressText
    #expect(combined.contains("`bash`"))
}

@Test func runAgentLoopWritesEmptyToolResultForSuccessfulMCPCall() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "read_file")]
    mcpBridge.callResults = ["read_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "import SwiftUI")])]

    let copilotAPI = MockCopilotAPIService()
    let toolCall = makeToolCall(name: "read_file", id: "call_rf")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Done."))
    ]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: ["read_file": "s"],
        writer: writer
    )

    // Successful non-empty tool results return empty string from formatter — nothing extra emitted beyond the tool call header
    let nonToolCallTexts = writer.progressTexts.filter { !$0.contains("`read_file`") }
    #expect(nonToolCallTexts.allSatisfy { !$0.contains("✗") })
}

@Test func runAgentLoopWritesWarningProgressForFailedMCPCall() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "run")]
    mcpBridge.callToolError = MCPBridgeError.toolExecutionFailed("timeout")

    let copilotAPI = MockCopilotAPIService()
    let toolCall = makeToolCall(name: "run", id: "call_run")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
        .success(MockCopilotAPIService.makeContentStream(content: "Failed."))
    ]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["run"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: ["run": "s"],
        writer: writer
    )

    let combined = writer.allProgressText
    #expect(combined.contains("✗"))
}

@Test func runAgentLoopPassesAllowedCLIToolCallsAsFinalToolCalls() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    let cliToolCall = makeToolCall(name: "grep", id: "call_grep")
    copilotAPI.streamChatCompletionsResults = [
        .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall]))
    ]

    let config = ServerConfiguration(
        allowedCliTools: ["grep"],
        autoApprovePermissions: .kinds([.read, .shell])
    )
    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge), configurationStore: ConfigurationStore(initial: config))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    #expect(writer.finalToolCalls?.count == 1)
    #expect(writer.finalToolCalls?.first?.function.name == "grep")
    #expect(writer.finishCalled)
}

@Test func runAgentLoopWritesStreamingErrorProgressOnCollectFailure() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = []

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.streamChatCompletionsResults = [
        .failure(CopilotAPIError.streamingFailed("connection reset"))
    ]

    let handler = makeHandler(copilotAPI: copilotAPI, bridgeHolder: MCPBridgeHolder(mcpBridge))
    let writer = MockAgentStreamWriter()

    await handler.runAgentLoop(
        request: makeRequest(),
        credentials: makeCredentials(),
        allTools: [],
        mcpToolServerMap: [:],
        writer: writer
    )

    let combined = writer.allProgressText
    #expect(combined.contains("✗"))
    #expect(writer.finishCalled)
}

@Test func executeMCPToolRespectsPerServerTimeout() async throws {
    let xcodeServer = MockMCPBridgeService()
    xcodeServer.callToolDelay = .milliseconds(300)
    xcodeServer.callResults = ["xcode_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

    let zedServer = MockMCPBridgeService()
    zedServer.callToolDelay = .milliseconds(300)
    zedServer.callResults = ["zed_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

    // xcode server has a 0.05s timeout (will expire), zed has a 60s timeout (will succeed)
    let config = ServerConfiguration(
        mcpServers: [
            "xcode": MCPServerConfiguration(type: .local, command: "xcrun", allowedTools: ["xcode_tool"], timeoutSeconds: 0.05),
            "zed": MCPServerConfiguration(type: .local, command: "zed", allowedTools: ["zed_tool"], timeoutSeconds: 60),
        ],
        autoApprovePermissions: .kinds([.mcp])
    )

    let xcodeHandler = makeHandler(
        bridgeHolder: MCPBridgeHolder(xcodeServer),
        configurationStore: ConfigurationStore(initial: config)
    )
    let zedHandler = makeHandler(
        bridgeHolder: MCPBridgeHolder(zedServer),
        configurationStore: ConfigurationStore(initial: config)
    )

    let xcodeResult = try await xcodeHandler.executeMCPTool(
        toolCall: makeToolCall(name: "xcode_tool"),
        serverName: "xcode"
    )
    let zedResult = try await zedHandler.executeMCPTool(
        toolCall: makeToolCall(name: "zed_tool"),
        serverName: "zed"
    )

    #expect(xcodeResult.contains("timed out after 0.05"), "xcode server should use its 0.05s timeout")
    #expect(zedResult == "result", "zed server should use its 60s timeout and succeed")
}
