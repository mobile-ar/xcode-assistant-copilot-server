@testable import XcodeAssistantCopilotServer
import Testing

private func makeResponse(
    status: String = "ok",
    uptimeSeconds: Int = 120,
    mcpBridgeEnabled: Bool = false,
    authState: AuthenticationState = .notConnected,
    copilotTokenExpiry: String? = nil,
    lastModelFetchTime: String? = nil
) -> HealthResponse {
    HealthResponse(
        status: status,
        uptimeSeconds: uptimeSeconds,
        mcpBridge: MCPBridgeStatus(enabled: mcpBridgeEnabled),
        authentication: AuthenticationStatus(state: authState, copilotTokenExpiry: copilotTokenExpiry),
        lastModelFetchTime: lastModelFetchTime
    )
}

@Test func renderContainsHTMLDoctype() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse())
    #expect(html.contains("<!DOCTYPE html>"))
}

@Test func renderContainsPageTitle() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse())
    #expect(html.contains("<title>Xcode Assistant Copilot"))
}

@Test func renderContainsStatusText() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(status: "ok"))
    #expect(html.contains("OK"))
}

@Test func renderContainsUptimeHumanReadable() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(uptimeSeconds: 120))
    #expect(html.contains("2m 0s"))
}

@Test func renderContainsUptimeRawSeconds() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(uptimeSeconds: 120))
    #expect(html.contains("120"))
}

@Test func renderShowsMCPBridgeEnabled() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(mcpBridgeEnabled: true))
    #expect(html.contains("Enabled"))
}

@Test func renderShowsMCPBridgeDisabled() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(mcpBridgeEnabled: false))
    #expect(html.contains("Disabled"))
}

@Test func renderShowsAuthenticated() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(authState: .authenticated))
    #expect(html.contains("Authenticated"))
}

@Test func renderShowsTokenExpired() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(authState: .tokenExpired))
    #expect(html.contains("Token Expired"))
}

@Test func renderShowsNotConnected() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(authState: .notConnected))
    #expect(html.contains("Not Connected"))
}

@Test func renderShowsTokenExpiry() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(authState: .tokenExpired, copilotTokenExpiry: "2025-01-01T00:00:00Z"))
    #expect(html.contains("2025-01-01T00:00:00Z"))
}

@Test func renderShowsNeverForNilFetchTime() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(lastModelFetchTime: nil))
    #expect(html.contains("Never"))
}

@Test func renderShowsFetchTimeWhenPresent() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(lastModelFetchTime: "2025-01-01T12:00:00Z"))
    #expect(html.contains("2025-01-01T12:00:00Z"))
}

@Test func renderFormatsUptimeSeconds() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(uptimeSeconds: 45))
    #expect(html.contains("45s"))
}

@Test func renderFormatsUptimeHours() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(uptimeSeconds: 4530))
    #expect(html.contains("1h 15m 30s"))
}

@Test func renderFormatsUptimeDays() {
    let renderer = HealthHTMLRenderer()
    let html = renderer.render(makeResponse(uptimeSeconds: 183900))
    #expect(html.contains("2d 3h 5m"))
}