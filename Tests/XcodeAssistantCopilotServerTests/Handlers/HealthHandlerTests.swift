@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

private func makeHandler(
    mcpBridge: MCPBridgeServiceProtocol? = nil,
    logger: LoggerProtocol = MockLogger(),
    startTime: Date = Date()
) -> HealthHandler {
    HealthHandler(
        mcpBridge: mcpBridge,
        logger: logger,
        startTime: startTime
    )
}

@Test func healthReturnsOkStatus() {
    let handler = makeHandler()

    let response = handler.buildHealthResponse()

    #expect(response.status == "ok")
}

@Test func healthReportsUptimeSeconds() {
    let startTime = Date().addingTimeInterval(-120)
    let handler = makeHandler(startTime: startTime)

    let response = handler.buildHealthResponse()

    #expect(response.uptimeSeconds >= 120)
    #expect(response.uptimeSeconds <= 125)
}

@Test func healthReportsZeroUptimeWhenJustStarted() {
    let handler = makeHandler(startTime: Date())

    let response = handler.buildHealthResponse()

    #expect(response.uptimeSeconds >= 0)
    #expect(response.uptimeSeconds <= 2)
}

@Test func healthReportsMCPBridgeDisabledWhenNoBridge() {
    let handler = makeHandler(mcpBridge: nil)

    let response = handler.buildHealthResponse()

    #expect(response.mcpBridge.enabled == false)
}

@Test func healthReportsMCPBridgeEnabledWhenBridgePresent() {
    let bridge = MockMCPBridgeService()
    let handler = makeHandler(mcpBridge: bridge)

    let response = handler.buildHealthResponse()

    #expect(response.mcpBridge.enabled == true)
}

@Test func healthResponseEncodesToExpectedJSON() throws {
    let startTime = Date().addingTimeInterval(-60)
    let handler = makeHandler(startTime: startTime)

    let response = handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["status"] as? String == "ok")
    #expect(json["uptime_seconds"] as? Int != nil)
    #expect(json["mcp_bridge"] as? [String: Any] != nil)

    let mcpBridge = json["mcp_bridge"] as? [String: Bool]
    #expect(mcpBridge?["enabled"] == false)
}

@Test func healthResponseEncodesEnabledBridgeToJSON() throws {
    let bridge = MockMCPBridgeService()
    let handler = makeHandler(mcpBridge: bridge)

    let response = handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let mcpBridge = json["mcp_bridge"] as? [String: Bool]
    #expect(mcpBridge?["enabled"] == true)
}