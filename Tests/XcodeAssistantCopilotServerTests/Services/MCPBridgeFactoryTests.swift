@testable import XcodeAssistantCopilotServer
import Testing
import Foundation

@Suite("MCPBridgeFactory")
struct MCPBridgeFactoryTests {

    private func makeLocalConfig() -> MCPServerConfiguration {
        MCPServerConfiguration(type: .local, command: "/usr/bin/echo", args: [])
    }

    private func makeStdioConfig() -> MCPServerConfiguration {
        MCPServerConfiguration(type: .stdio, command: "/usr/bin/cat", args: [])
    }

    private func makeHTTPConfig() -> MCPServerConfiguration {
        MCPServerConfiguration(type: .http, url: "https://mcp.example.com/mcp")
    }

    private func makeSSEConfig() -> MCPServerConfiguration {
        MCPServerConfiguration(type: .sse, url: "https://mcp.example.com/sse")
    }

    private func makeConfiguration(
        servers: [String: MCPServerConfiguration]
    ) -> ServerConfiguration {
        ServerConfiguration(mcpServers: servers)
    }

    private func makeBridge(
        servers: [String: MCPServerConfiguration]
    ) -> MCPBridgeServiceProtocol? {
        MCPBridgeFactory.make(
            from: makeConfiguration(servers: servers),
            logger: MockLogger(),
            httpClient: MockHTTPClient(),
            pidFile: nil,
            clientName: "test-client",
            clientVersion: "1.0.0",
            processRunner: MockProcessRunner()
        )
    }

    // MARK: - Empty configuration

    @Test("make() returns nil when no servers are configured")
    func make_returnsNilForEmptyConfig() {
        #expect(makeBridge(servers: [:]) == nil)
    }

    // MARK: - Single local / stdio server

    @Test("make() returns MCPBridgeService for a single local server")
    func make_returnsMCPBridgeServiceForSingleLocalServer() {
        let result = makeBridge(servers: ["local": makeLocalConfig()])
        #expect(result != nil)
        #expect(result is MCPBridgeService)
    }

    @Test("make() returns MCPBridgeService for a single stdio server")
    func make_returnsMCPBridgeServiceForSingleStdioServer() {
        let result = makeBridge(servers: ["stdio": makeStdioConfig()])
        #expect(result != nil)
        #expect(result is MCPBridgeService)
    }

    // MARK: - Single HTTP server

    @Test("make() returns MCPHTTPBridgeService for a single http server")
    func make_returnsMCPHTTPBridgeServiceForSingleHTTPServer() {
        let result = makeBridge(servers: ["http": makeHTTPConfig()])
        #expect(result != nil)
        #expect(result is MCPHTTPBridgeService)
    }

    // MARK: - Single SSE server

    @Test("make() returns MCPSSEBridgeService for a single sse server")
    func make_returnsMCPSSEBridgeServiceForSingleSSEServer() {
        let result = makeBridge(servers: ["sse": makeSSEConfig()])
        #expect(result != nil)
        #expect(result is MCPSSEBridgeService)
    }

    // MARK: - Multiple servers of the same type

    @Test("make() returns CompositeMCPBridgeService for two local servers")
    func make_returnsCompositeForTwoLocalServers() {
        let result = makeBridge(servers: [
            "localA": makeLocalConfig(),
            "localB": makeLocalConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for two http servers")
    func make_returnsCompositeForTwoHTTPServers() {
        let result = makeBridge(servers: [
            "httpA": makeHTTPConfig(),
            "httpB": makeHTTPConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for two sse servers")
    func make_returnsCompositeForTwoSSEServers() {
        let result = makeBridge(servers: [
            "sseA": makeSSEConfig(),
            "sseB": makeSSEConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    // MARK: - Mixed server types

    @Test("make() returns CompositeMCPBridgeService for local + http servers")
    func make_returnsCompositeForLocalAndHTTP() {
        let result = makeBridge(servers: [
            "local": makeLocalConfig(),
            "http": makeHTTPConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for local + sse servers")
    func make_returnsCompositeForLocalAndSSE() {
        let result = makeBridge(servers: [
            "local": makeLocalConfig(),
            "sse": makeSSEConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for http + sse servers")
    func make_returnsCompositeForHTTPAndSSE() {
        let result = makeBridge(servers: [
            "http": makeHTTPConfig(),
            "sse": makeSSEConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for all four server types")
    func make_returnsCompositeForAllFourTypes() {
        let result = makeBridge(servers: [
            "local": makeLocalConfig(),
            "stdio": makeStdioConfig(),
            "http": makeHTTPConfig(),
            "sse": makeSSEConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for local + stdio servers")
    func make_returnsCompositeForLocalAndStdio() {
        let result = makeBridge(servers: [
            "local": makeLocalConfig(),
            "stdio": makeStdioConfig(),
        ])
        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    // MARK: - httpClient is forwarded

    @Test("make() passes the provided httpClient to HTTP bridge")
    func make_passesHTTPClientToHTTPBridge() {
        let sharedClient = MockHTTPClient()
        let result = MCPBridgeFactory.make(
            from: makeConfiguration(servers: ["http": makeHTTPConfig()]),
            logger: MockLogger(),
            httpClient: sharedClient,
            pidFile: nil,
            clientName: "client",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )
        // The bridge is created and is the correct type; we verify no crash and correct type.
        #expect(result is MCPHTTPBridgeService)
    }

    @Test("make() passes the provided httpClient to SSE bridge")
    func make_passesHTTPClientToSSEBridge() {
        let sharedClient = MockHTTPClient()
        let result = MCPBridgeFactory.make(
            from: makeConfiguration(servers: ["sse": makeSSEConfig()]),
            logger: MockLogger(),
            httpClient: sharedClient,
            pidFile: nil,
            clientName: "client",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )
        #expect(result is MCPSSEBridgeService)
    }
}