@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Testing

private func makeHandler(
    authService: AuthServiceProtocol = MockAuthService(),
    copilotAPI: CopilotAPIServiceProtocol = MockCopilotAPIService(),
    mcpBridge: MCPBridgeServiceProtocol? = nil,
    modelEndpointResolver: ModelEndpointResolverProtocol = MockModelEndpointResolver(),
    reasoningEffortResolver: ReasoningEffortResolverProtocol = MockReasoningEffortResolver(),
    configuration: ServerConfiguration = ServerConfiguration(),
    logger: LoggerProtocol = MockLogger()
) -> ChatCompletionsHandler {
    ChatCompletionsHandler(
        authService: authService,
        copilotAPI: copilotAPI,
        mcpBridge: mcpBridge,
        modelEndpointResolver: modelEndpointResolver,
        reasoningEffortResolver: reasoningEffortResolver,
        configuration: configuration,
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

@Test func executeMCPToolReturnsBridgeNotAvailableWhenNoBridge() async {
    let handler = makeHandler(mcpBridge: nil)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("MCP bridge not available"))
}

@Test func executeMCPToolBlockedWhenMCPPermissionNotApproved() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "search")]
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read])
    )
    let handler = makeHandler(
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("MCP tool execution is not approved"))
    #expect(result.contains("autoApprovePermissions"))
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(logger.warnMessages.contains { $0.contains("not approved") })
}

@Test func executeMCPToolBlockedWhenAllPermissionsFalse() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "read_file")]
    mcpBridge.callResults = ["read_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "content")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
        autoApprovePermissions: .all(false)
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "read_file")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not approved"))
    #expect(mcpBridge.calledTools.isEmpty)
}

@Test func executeMCPToolBlockedWhenToolNotInAllowList() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.tools = [MCPTool(name: "delete_file")]
    mcpBridge.callResults = ["delete_file": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "deleted")])]

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search", "read"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )
    let toolCall = makeToolCall(name: "delete_file")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not allowed by server configuration"))
    #expect(result.contains("delete_file"))
    #expect(mcpBridge.calledTools.isEmpty)
    #expect(logger.warnMessages.contains { $0.contains("not in the allowed tools list") })
}

@Test func executeMCPToolBlockedWhenNoMCPServersConfigured() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found")])]

    let config = ServerConfiguration(
        mcpServers: [:],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("not allowed by server configuration"))
    #expect(mcpBridge.calledTools.isEmpty)
}

@Test func executeMCPToolAllowedWhenPermissionAndAllowListPass() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "found it")])]

    let config = ServerConfiguration(
        mcpServers: ["server1": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.read, .mcp])
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "found it")
    #expect(mcpBridge.calledTools.count == 1)
    #expect(mcpBridge.calledTools[0].name == "search")
}

@Test func executeMCPToolAllowedWhenAllPermissionsTrue() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["search": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "result")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .all(true)
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "result")
    #expect(mcpBridge.calledTools.count == 1)
}

@Test func executeMCPToolAllowedWithWildcardInAllowedTools() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callResults = ["any_tool": MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])]

    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["*"])],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "any_tool")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result == "ok")
}

@Test func executeMCPToolReturnsErrorWhenBridgeCallFails() async {
    let mcpBridge = MockMCPBridgeService()
    mcpBridge.callToolError = MCPToolError.executionFailed("timeout")

    let logger = MockLogger()
    let config = ServerConfiguration(
        mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
        autoApprovePermissions: .kinds([.mcp])
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config, logger: logger)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

    #expect(result.contains("Error executing tool search"))
    #expect(logger.errorMessages.contains { $0.contains("search") && $0.contains("failed") })
}

@Test func executeMCPToolChecksPermissionBeforeAllowList() async {
    let mcpBridge = MockMCPBridgeService()
    let config = ServerConfiguration(
        mcpServers: [:],
        autoApprovePermissions: .kinds([.read])
    )
    let handler = makeHandler(mcpBridge: mcpBridge, configuration: config)
    let toolCall = makeToolCall(name: "search")

    let result = await handler.executeMCPTool(toolCall: toolCall)

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(logger.warnMessages.contains { $0.contains("rm") && $0.contains("blocked") })
    #expect(logger.infoMessages.contains { $0.contains("All CLI tool calls blocked, continuing agent loop") })
}

@Test func agentStreamingMCPToolExecutedAndStreamsFinalResponse() async {
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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(mcpBridge.calledTools.count == 1)
    #expect(logger.infoMessages.contains { $0.contains("MCP tool(s) executed, streaming final response") })
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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: ServerConfiguration(),
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        reasoningEffortResolver: reasoningResolver,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        reasoningEffortResolver: reasoningResolver,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        reasoningEffortResolver: reasoningResolver,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

    #expect(response.status == HTTPResponse.Status.internalServerError)
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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

    #expect(response.status == HTTPResponse.Status.internalServerError)
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
        mcpBridge: mcpBridge,
        configuration: config,
        logger: logger
    )

    let response = await handler.handleAgentStreaming(
        request: makeRequest(),
        credentials: makeCredentials()
    )

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.streamChatCompletionsCallCount == 2)
    #expect(logger.errorMessages.contains { $0.contains(detailedErrorBody) })
    #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .medium)
}

