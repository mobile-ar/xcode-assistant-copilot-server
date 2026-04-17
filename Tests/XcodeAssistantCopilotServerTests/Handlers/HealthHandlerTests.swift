@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

private func makeHandler(
    bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
    authService: AuthServiceProtocol = MockAuthService(),
    modelFetchCache: ModelFetchCache = ModelFetchCache(),
    logger: LoggerProtocol = MockLogger(),
    startTime: Date = Date()
) -> HealthHandler {
    HealthHandler(
        bridgeHolder: bridgeHolder,
        authService: authService,
        modelFetchCache: modelFetchCache,
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

@Test func healthReportsNotAuthenticatedWhenNoCachedToken() async {
    let authService = MockAuthService()
    authService.mockTokenInfo = nil
    let handler = makeHandler(authService: authService)

    let response = await handler.buildHealthResponse()

    #expect(response.authentication.state == .notConnected)
    #expect(response.authentication.copilotTokenExpiry == nil)
}

@Test func healthReportsAuthenticatedWhenValidTokenCached() async {
    let expiresAt = Date().addingTimeInterval(3600)
    let authService = MockAuthService()
    authService.mockTokenInfo = CopilotTokenInfo(expiresAt: expiresAt, isAuthenticated: true)
    let handler = makeHandler(authService: authService)

    let response = await handler.buildHealthResponse()

    #expect(response.authentication.state == .authenticated)
    #expect(response.authentication.copilotTokenExpiry != nil)
}

@Test func healthReportsTokenExpiredWhenExpiredTokenCached() async {
    let expiresAt = Date().addingTimeInterval(-60)
    let authService = MockAuthService()
    authService.mockTokenInfo = CopilotTokenInfo(expiresAt: expiresAt, isAuthenticated: false)
    let handler = makeHandler(authService: authService)

    let response = await handler.buildHealthResponse()

    #expect(response.authentication.state == .tokenExpired)
    #expect(response.authentication.copilotTokenExpiry != nil)
}

@Test func healthTokenExpiryIsISO8601Formatted() async throws {
    let expiresAt = Date().addingTimeInterval(3600)
    let authService = MockAuthService()
    authService.mockTokenInfo = CopilotTokenInfo(expiresAt: expiresAt, isAuthenticated: true)
    let handler = makeHandler(authService: authService)

    let response = await handler.buildHealthResponse()

    let expiry = try #require(response.authentication.copilotTokenExpiry)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let parsed = formatter.date(from: expiry)
    #expect(parsed != nil)
}

@Test func healthReportsNilLastModelFetchTimeWhenCacheEmpty() async {
    let handler = makeHandler(modelFetchCache: ModelFetchCache())

    let response = await handler.buildHealthResponse()

    #expect(response.lastModelFetchTime == nil)
}

@Test func healthReportsLastModelFetchTimeAfterRecordFetch() async throws {
    let cache = ModelFetchCache()
    await cache.recordFetch(models: [])
    let handler = makeHandler(modelFetchCache: cache)

    let response = await handler.buildHealthResponse()

    let fetchTime = try #require(response.lastModelFetchTime)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let parsed = formatter.date(from: fetchTime)
    #expect(parsed != nil)
}

@Test func healthLastModelFetchTimeUpdatesOnSubsequentFetches() async throws {
    let cache = ModelFetchCache()
    await cache.recordFetch(models: [])
    let handler = makeHandler(modelFetchCache: cache)

    let first = await handler.buildHealthResponse()

    try await Task.sleep(for: .milliseconds(10))
    await cache.recordFetch(models: [])

    let second = await handler.buildHealthResponse()

    let firstTime = try #require(first.lastModelFetchTime)
    let secondTime = try #require(second.lastModelFetchTime)
    #expect(firstTime != secondTime)
}

@Test func healthResponseJSONIncludesAuthenticationFields() async throws {
    let expiresAt = Date().addingTimeInterval(3600)
    let authService = MockAuthService()
    authService.mockTokenInfo = CopilotTokenInfo(expiresAt: expiresAt, isAuthenticated: true)
    let handler = makeHandler(authService: authService)

    let response = await handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let authentication = try #require(json["authentication"] as? [String: Any])
    #expect(authentication["state"] as? String == "authenticated")
    #expect(authentication["copilot_token_expiry"] as? String != nil)
}

@Test func healthResponseJSONOmitsLastModelFetchTimeWhenNotFetched() async throws {
    let handler = makeHandler(modelFetchCache: ModelFetchCache())

    let response = await handler.buildHealthResponse()

    let encoder = JSONEncoder()
    let data = try encoder.encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(!json.keys.contains("last_model_fetch_time"))
}

@Test func healthResponseJSONIncludesLastModelFetchTimeAfterFetch() async throws {
    let cache = ModelFetchCache()
    await cache.recordFetch(models: [])
    let handler = makeHandler(modelFetchCache: cache)

    let response = await handler.buildHealthResponse()
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["last_model_fetch_time"] as? String != nil)
}