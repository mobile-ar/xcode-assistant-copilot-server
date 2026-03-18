@testable import XcodeAssistantCopilotServer
import Testing
import Foundation

@Suite("MCPBridgeFactory")
struct MCPBridgeFactoryTests {

    private func makeServerConfig(type: MCPServerType) -> MCPServerConfiguration {
        MCPServerConfiguration(
            type: type,
            command: "/usr/bin/echo",
            args: []
        )
    }

    private func makeConfiguration(servers: [String: MCPServerConfiguration]) -> ServerConfiguration {
        ServerConfiguration(mcpServers: servers)
    }

    @Test("make() returns nil when no servers are configured")
    func make_returnsNilWhenNoServers() {
        let configuration = makeConfiguration(servers: [:])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result == nil)
    }

    @Test("make() returns nil when only http servers are configured")
    func make_returnsNilForHttpOnly() {
        let configuration = makeConfiguration(servers: [
            "httpServer": makeServerConfig(type: .http),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result == nil)
    }

    @Test("make() returns nil when only sse servers are configured")
    func make_returnsNilForSseOnly() {
        let configuration = makeConfiguration(servers: [
            "sseServer": makeServerConfig(type: .sse),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result == nil)
    }

    @Test("make() returns nil when only http and sse servers are configured")
    func make_returnsNilForHttpAndSseMixed() {
        let configuration = makeConfiguration(servers: [
            "httpServer": makeServerConfig(type: .http),
            "sseServer": makeServerConfig(type: .sse),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result == nil)
    }

    @Test("make() returns a single MCPBridgeService for one local server")
    func make_returnsSingleBridgeForOneLocalServer() {
        let configuration = makeConfiguration(servers: [
            "localServer": makeServerConfig(type: .local),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
        #expect(result is MCPBridgeService)
    }

    @Test("make() returns a single MCPBridgeService for one stdio server")
    func make_returnsSingleBridgeForOneStdioServer() {
        let configuration = makeConfiguration(servers: [
            "stdioServer": makeServerConfig(type: .stdio),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
        #expect(result is MCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for multiple local servers")
    func make_returnsCompositeBridgeForMultipleLocalServers() {
        let configuration = makeConfiguration(servers: [
            "serverA": makeServerConfig(type: .local),
            "serverB": makeServerConfig(type: .local),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() returns CompositeMCPBridgeService for mixed local and stdio servers")
    func make_returnsCompositeBridgeForMixedLocalAndStdio() {
        let configuration = makeConfiguration(servers: [
            "localServer": makeServerConfig(type: .local),
            "stdioServer": makeServerConfig(type: .stdio),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
        #expect(result is CompositeMCPBridgeService)
    }

    @Test("make() ignores http and sse servers when local servers are also present")
    func make_ignoresHttpAndSseWhenLocalAlsoPresent() {
        let configuration = makeConfiguration(servers: [
            "localServer": makeServerConfig(type: .local),
            "httpServer": makeServerConfig(type: .http),
            "sseServer": makeServerConfig(type: .sse),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "test",
            clientVersion: "1.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
        #expect(result is MCPBridgeService)
    }

    @Test("make() passes clientName and clientVersion to the bridge")
    func make_passesClientInfo() {
        let configuration = makeConfiguration(servers: [
            "localServer": makeServerConfig(type: .local),
        ])

        let result = MCPBridgeFactory.make(
            from: configuration,
            logger: MockLogger(),
            pidFile: nil,
            clientName: "my-client",
            clientVersion: "2.5.0",
            processRunner: MockProcessRunner()
        )

        #expect(result != nil)
    }
}
