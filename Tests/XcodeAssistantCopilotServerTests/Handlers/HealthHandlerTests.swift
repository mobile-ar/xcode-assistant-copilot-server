@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

private func makeHandler(
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    logger: LoggerProtocol = MockLogger(),
    startTime: Date = Date()
) -> HealthHandler {
    HealthHandler(
        bridgeHolder: bridgeHolder,
        logger: logger,
        startTime: startTime
    )
}

@Test func healthReturnsOkStatus() async {
    let handler = makeHandler()

    let response = await handler.buildHealthResponse()

    #expect(response.status == "ok")
}

@Test func healthReportsUptimeSeconds() async {
    let startTime = Date().addingTimeInterval(-120)
    let handler = makeHandler(startTime: startTime)

    let response = await handler.buildHealthResponse()

    #expect(response.uptimeSeconds >= 120)
    #expect(response.uptimeSeconds <= 125)
}

@Test func healthReportsZeroUptimeWhenJustStarted() async {
    let handler = makeHandler(startTime: Date())

    let response = await handler.buildHealthResponse()

    #expect(response.uptimeSeconds >= 0)
    #expect(response.uptimeSeconds <= 2)
}

@Test func healthReportsMCPBridgeDisabledWhenNoBridge() async {
    let handler = makeHandler(bridgeHolder: MCPBridgeHolder())

    let response = await handler.buildHealthResponse()

    #expect(response.mcpBridge.enabled == false)
}

@Test func healthReportsMCPBridgeEnabledWhenBridgePresent() async {
    let holder = MCPBridgeHolder(MockMCPBridgeService())
    let handler = makeHandler(bridgeHolder: holder)

    let response = await handler.buildHealthResponse()

    #expect(response.mcpBridge.enabled == true)
}



@Test func healthResponseEncodesToExpectedJSON() async throws {
    let startTime = Date().addingTimeInterval(-60)
    let handler = makeHandler(startTime: startTime)

    let response = await handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["status"] as? String == "ok")
    #expect(json["uptime_seconds"] as? Int != nil)
    #expect(json["mcp_bridge"] as? [String: Any] != nil)

    let mcpBridge = json["mcp_bridge"] as? [String: Bool]
    #expect(mcpBridge?["enabled"] == false)
}

@Test func healthResponseEncodesEnabledBridgeToJSON() async throws {
    let holder = MCPBridgeHolder(MockMCPBridgeService())
    let handler = makeHandler(bridgeHolder: holder)

    let response = await handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let mcpBridge = json["mcp_bridge"] as? [String: Bool]
    #expect(mcpBridge?["enabled"] == true)
}

@Test func healthReportsBridgeDisabledAfterBridgeIsRemoved() async {
    let bridge = MockMCPBridgeService()
    let holder = MCPBridgeHolder(bridge)
    let handler = makeHandler(bridgeHolder: holder)

    let before = await handler.buildHealthResponse()
    #expect(before.mcpBridge.enabled == true)

    await holder.setBridge(nil)

    let after = await handler.buildHealthResponse()
    #expect(after.mcpBridge.enabled == false)
}

@Test func healthReportsBridgeEnabledAfterBridgeIsSet() async {
    let holder = MCPBridgeHolder()
    let handler = makeHandler(bridgeHolder: holder)

    let before = await handler.buildHealthResponse()
    #expect(before.mcpBridge.enabled == false)

    await holder.setBridge(MockMCPBridgeService())

    let after = await handler.buildHealthResponse()
    #expect(after.mcpBridge.enabled == true)
}