@testable import XcodeAssistantCopilotServer
import Testing

@Test func mcpBridgeErrorNotStartedDescription() {
    let error = MCPBridgeError.notStarted
    #expect(error.description == "MCP bridge has not been started")
}

@Test func mcpBridgeErrorAlreadyStartedDescription() {
    let error = MCPBridgeError.alreadyStarted
    #expect(error.description == "MCP bridge is already running")
}

@Test func mcpBridgeErrorProcessSpawnFailedDescription() {
    let error = MCPBridgeError.processSpawnFailed("permission denied")
    #expect(error.description == "Failed to spawn mcpbridge process: permission denied")
}

@Test func mcpBridgeErrorInitializationFailedDescription() {
    let error = MCPBridgeError.initializationFailed("timeout")
    #expect(error.description == "MCP bridge initialization failed: timeout")
}

@Test func mcpBridgeErrorCommunicationFailedDescription() {
    let error = MCPBridgeError.communicationFailed("pipe broken")
    #expect(error.description == "MCP bridge communication failed: pipe broken")
}

@Test func mcpBridgeErrorToolExecutionFailedDescription() {
    let error = MCPBridgeError.toolExecutionFailed("tool crashed")
    #expect(error.description == "MCP bridge tool execution failed: tool crashed")
}

@Test func mcpBridgeErrorMcpBridgeNotFoundDescription() {
    let error = MCPBridgeError.mcpBridgeNotFound
    #expect(error.description == "xcrun mcpbridge not found. This requires Xcode 26.3 or later.")
}

@Test func mcpBridgeErrorConformsToErrorProtocol() {
    let error: Error = MCPBridgeError.notStarted
    #expect(error is MCPBridgeError)
}

@Test func mcpBridgeErrorAllCasesHaveNonEmptyDescriptions() {
    let cases: [MCPBridgeError] = [
        .notStarted,
        .alreadyStarted,
        .processSpawnFailed("msg"),
        .initializationFailed("msg"),
        .communicationFailed("msg"),
        .toolExecutionFailed("msg"),
        .mcpBridgeNotFound,
    ]

    for error in cases {
        #expect(!error.description.isEmpty)
    }
}