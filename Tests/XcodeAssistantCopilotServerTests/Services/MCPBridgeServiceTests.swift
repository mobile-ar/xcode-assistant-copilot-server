@testable import XcodeAssistantCopilotServer
import Testing
import Foundation

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

@Test("Throws mcpBridgeNotFound when xcrun --find exits with non-zero code")
func xcrunFindFailsWithNonZeroExit() async {
    let runner = MockProcessRunner(stdout: "", stderr: "not found", exitCode: 1)
    let bridge = MCPBridgeService(
        serverName: "xcode",
        serverConfig: MCPServerConfiguration(type: .local, command: "/usr/bin/xcrun"),
        logger: MockLogger(),
        clientName: "test",
        clientVersion: "0.0.0",
        processRunner: runner
    )

    do {
        try await bridge.start()
        Issue.record("Expected mcpBridgeNotFound to be thrown")
    } catch MCPBridgeError.mcpBridgeNotFound {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.mcpBridgeNotFound, got \(error)")
    }
}

@Test("Throws mcpBridgeNotFound when processRunner throws")
func xcrunFindThrows() async {
    let runner = MockProcessRunner(throwing: ProcessRunnerError.executableNotFound("/usr/bin/xcrun"))
    let bridge = MCPBridgeService(
        serverName: "xcode",
        serverConfig: MCPServerConfiguration(type: .local, command: "/usr/bin/xcrun"),
        logger: MockLogger(),
        clientName: "test",
        clientVersion: "0.0.0",
        processRunner: runner
    )

    do {
        try await bridge.start()
        Issue.record("Expected mcpBridgeNotFound to be thrown")
    } catch MCPBridgeError.mcpBridgeNotFound {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.mcpBridgeNotFound, got \(error)")
    }
}

@Test("Skips verification for non-xcrun commands")
func nonXcrunCommandSkipsVerification() async {
    let runner = MockProcessRunner(stdout: "", stderr: "", exitCode: 0)
    let bridge = MCPBridgeService(
        serverName: "custom",
        serverConfig: MCPServerConfiguration(type: .local, command: "/usr/local/bin/custom-bridge"),
        logger: MockLogger(),
        clientName: "test",
        clientVersion: "0.0.0",
        processRunner: runner
    )

    // start() will fail trying to spawn the real process, but verifyMCPBridgeExists
    // must NOT have invoked the runner (it only checks xcrun commands), so no
    // mcpBridgeNotFound error should be thrown.
    do {
        try await bridge.start()
    } catch MCPBridgeError.mcpBridgeNotFound {
        Issue.record("verifyMCPBridgeExists should not be called for non-xcrun commands")
    } catch {
        // Other errors (process spawn) are expected in a test environment
    }
}
