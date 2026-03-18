@testable import XcodeAssistantCopilotServer
import Testing
import Foundation

@Suite("CompositeMCPBridgeService")
struct CompositeMCPBridgeServiceTests {

    @Test("start() starts all child bridges")
    func start_startsAllChildBridges() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: MockLogger()
        )

        try await composite.start()

        #expect(bridgeA.startCallCount == 1)
        #expect(bridgeB.startCallCount == 1)
    }

    @Test("start() continues when one bridge fails to start")
    func start_continuesWhenOneBridgeFails() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.startError = MCPBridgeError.processSpawnFailed("boom")
        let logger = MockLogger()
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: logger
        )

        try await composite.start()

        #expect(bridgeB.startCallCount == 1)
        #expect(logger.warnMessages.contains { $0.contains("a") && $0.contains("skipping") })
    }

    @Test("stop() stops all started bridges")
    func stop_stopsAllStartedBridges() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: MockLogger()
        )

        try await composite.start()
        try await composite.stop()

        #expect(bridgeA.stopCallCount == 1)
        #expect(bridgeB.stopCallCount == 1)
    }

    @Test("stop() only stops bridges that were successfully started")
    func stop_onlyStopsBridgesThatStarted() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.startError = MCPBridgeError.processSpawnFailed("boom")
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: MockLogger()
        )

        try await composite.start()
        try await composite.stop()

        #expect(bridgeA.stopCallCount == 0)
        #expect(bridgeB.stopCallCount == 1)
    }

    @Test("stop() clears tool cache so next listTools() re-queries bridges")
    func stop_clearsCacheForNextListTools() async throws {
        let bridgeA = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        let composite = CompositeMCPBridgeService(
            bridges: [(serverName: "a", bridge: bridgeA)],
            logger: MockLogger()
        )

        try await composite.start()
        _ = try await composite.listTools()
        #expect(bridgeA.listToolsCallCount == 1)

        try await composite.stop()
        try await composite.start()
        _ = try await composite.listTools()
        #expect(bridgeA.listToolsCallCount == 2)
    }

    @Test("listTools() merges tools from all bridges")
    func listTools_mergesToolsFromAllBridges() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA", description: "from A")]
        bridgeB.tools = [MCPTool(name: "toolB", description: "from B")]
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: MockLogger()
        )

        try await composite.start()
        let tools = try await composite.listTools()

        let names = tools.map(\.name)
        #expect(names.contains("toolA"))
        #expect(names.contains("toolB"))
        #expect(tools.count == 2)
    }

    @Test("listTools() returns cached result on second call")
    func listTools_returnsCachedResult() async throws {
        let bridgeA = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        let composite = CompositeMCPBridgeService(
            bridges: [(serverName: "a", bridge: bridgeA)],
            logger: MockLogger()
        )

        try await composite.start()
        _ = try await composite.listTools()
        _ = try await composite.listTools()

        #expect(bridgeA.listToolsCallCount == 1)
    }

    @Test("listTools() skips bridge that throws and returns remaining tools")
    func listTools_skipsBridgeThatThrows() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.listToolsError = MCPBridgeError.communicationFailed("pipe broken")
        bridgeB.tools = [MCPTool(name: "toolB")]
        let logger = MockLogger()
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: logger
        )

        try await composite.start()
        let tools = try await composite.listTools()

        #expect(tools.map(\.name) == ["toolB"])
        #expect(logger.warnMessages.contains { $0.contains("skipping") })
    }

    @Test("listTools() first bridge wins on tool name collision")
    func listTools_firstBridgeWinsOnCollision() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "shared", description: "from A")]
        bridgeB.tools = [MCPTool(name: "shared", description: "from B")]
        let logger = MockLogger()
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: logger
        )

        try await composite.start()
        let tools = try await composite.listTools()

        #expect(tools.count == 1)
        #expect(tools.first?.description == "from A")
        #expect(logger.warnMessages.contains { $0.contains("conflict") && $0.contains("shared") })
    }

    @Test("callTool() dispatches to the bridge that owns the tool")
    func callTool_dispatchesToCorrectBridge() async throws {
        let bridgeA = MockMCPBridgeService()
        let bridgeB = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        bridgeB.tools = [MCPTool(name: "toolB")]
        let expectedResult = MCPToolResult(content: [MCPToolResultContent(type: "text", text: "done")])
        bridgeB.callResults = ["toolB": expectedResult]
        let composite = CompositeMCPBridgeService(
            bridges: [
                (serverName: "a", bridge: bridgeA),
                (serverName: "b", bridge: bridgeB),
            ],
            logger: MockLogger()
        )

        try await composite.start()
        let result = try await composite.callTool(name: "toolB", arguments: [:])

        #expect(result.textContent == "done")
        #expect(bridgeA.calledTools.isEmpty)
        #expect(bridgeB.calledTools.count == 1)
        #expect(bridgeB.calledTools.first?.name == "toolB")
    }

    @Test("callTool() throws when tool is not registered to any bridge")
    func callTool_throwsWhenToolUnknown() async throws {
        let bridgeA = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        let composite = CompositeMCPBridgeService(
            bridges: [(serverName: "a", bridge: bridgeA)],
            logger: MockLogger()
        )

        try await composite.start()

        await #expect(throws: MCPBridgeError.toolExecutionFailed("No bridge found for tool: unknown")) {
            _ = try await composite.callTool(name: "unknown", arguments: [:])
        }
    }

    @Test("callTool() triggers listTools() lazily when tool map is empty")
    func callTool_populatesToolMapLazily() async throws {
        let bridgeA = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        let expectedResult = MCPToolResult(content: [MCPToolResultContent(type: "text", text: "ok")])
        bridgeA.callResults = ["toolA": expectedResult]
        let composite = CompositeMCPBridgeService(
            bridges: [(serverName: "a", bridge: bridgeA)],
            logger: MockLogger()
        )

        try await composite.start()
        let result = try await composite.callTool(name: "toolA", arguments: [:])

        #expect(result.textContent == "ok")
        #expect(bridgeA.listToolsCallCount == 1)
    }

    @Test("callTool() forwards arguments to the owning bridge")
    func callTool_forwardsArguments() async throws {
        let bridgeA = MockMCPBridgeService()
        bridgeA.tools = [MCPTool(name: "toolA")]
        bridgeA.callResults = ["toolA": MCPToolResult(content: [])]
        let composite = CompositeMCPBridgeService(
            bridges: [(serverName: "a", bridge: bridgeA)],
            logger: MockLogger()
        )

        let args: [String: AnyCodable] = ["key": AnyCodable(.string("value"))]
        try await composite.start()
        _ = try await composite.callTool(name: "toolA", arguments: args)

        #expect(bridgeA.calledTools.first?.arguments["key"]?.stringValue == "value")
    }
}
