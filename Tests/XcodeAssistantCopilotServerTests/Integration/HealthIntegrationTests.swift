@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@Suite("Health endpoint integration")
struct HealthIntegrationTests {

    @Test("GET /health returns 200 OK")
    func healthReturns200() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            #expect(response.status == .ok)
        }
    }

    @Test("GET /health response body is valid JSON with status ok")
    func healthBodyContainsStatusOk() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            #expect(json["status"] as? String == "ok")
        }
    }

    @Test("GET /health response body includes uptime_seconds field")
    func healthBodyContainsUptimeSeconds() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            #expect(json["uptime_seconds"] as? Int != nil)
        }
    }

    @Test("GET /health response has application/json content-type")
    func healthResponseHasJSONContentType() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            #expect(response.headers[.contentType] == "application/json")
        }
    }

    @Test("GET /health response includes CORS allow-origin header")
    func healthResponseIncludesCORSHeader() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
        }
    }

    @Test("GET /health bypasses Xcode user-agent requirement")
    func healthBypassesUserAgentCheck() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.userAgent: "curl/8.0"]
            )
            #expect(response.status == .ok)
        }
    }

    @Test("GET /health shows mcp_bridge.enabled false when no bridge is active")
    func healthShowsBridgeDisabled() async throws {
        let harness = ServerTestHarness(bridgeHolder: MCPBridgeHolder())
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            let bridge = try #require(json["mcp_bridge"] as? [String: Any])
            #expect(bridge["enabled"] as? Bool == false)
        }
    }

    @Test("GET /health shows mcp_bridge.enabled true when a bridge is active")
    func healthShowsBridgeEnabled() async throws {
        let harness = ServerTestHarness(bridgeHolder: MCPBridgeHolder(MockMCPBridgeService()))
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            let bridge = try #require(json["mcp_bridge"] as? [String: Any])
            #expect(bridge["enabled"] as? Bool == true)
        }
    }

    @Test("GET /health shows authentication.authenticated false when no token info is cached")
    func healthShowsNotAuthenticatedWithNoToken() async throws {
        let authService = MockAuthService()
        authService.mockTokenInfo = nil
        let harness = ServerTestHarness(authService: authService)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            let auth = try #require(json["authentication"] as? [String: Any])
            #expect(auth["state"] as? String == "not_connected")
        }
    }

    @Test("GET /health shows authentication.authenticated true when a valid token is cached")
    func healthShowsAuthenticatedWithValidToken() async throws {
        let authService = MockAuthService()
        authService.mockTokenInfo = CopilotTokenInfo(
            expiresAt: Date().addingTimeInterval(3600),
            isAuthenticated: true
        )
        let harness = ServerTestHarness(authService: authService)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            let auth = try #require(json["authentication"] as? [String: Any])
            #expect(auth["state"] as? String == "authenticated")
        }
    }

    @Test("GET /health shows authentication.copilot_token_expiry when token is cached")
    func healthShowsTokenExpiryWhenAuthenticated() async throws {
        let authService = MockAuthService()
        authService.mockTokenInfo = CopilotTokenInfo(
            expiresAt: Date().addingTimeInterval(3600),
            isAuthenticated: true
        )
        let harness = ServerTestHarness(authService: authService)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            let auth = try #require(json["authentication"] as? [String: Any])
            #expect(auth["copilot_token_expiry"] as? String != nil)
        }
    }

    @Test("GET /health omits last_model_fetch_time when no models have been fetched")
    func healthOmitsLastModelFetchTimeWhenCacheEmpty() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            #expect(!json.keys.contains("last_model_fetch_time"))
        }
    }

    @Test("GET /health returns HTML when Accept header contains text/html")
    func healthReturnsHTMLWhenAcceptIsTextHTML() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html"]
            )
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/html; charset=utf-8")
        }
    }

    @Test("GET /health returns HTML body with DOCTYPE when browser Accept header is sent")
    func healthReturnsHTMLBodyForBrowserAccept() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]
            )
            let body = String(buffer: response.body)
            #expect(body.contains("<!DOCTYPE html>"))
            #expect(body.contains("Xcode Assistant Copilot"))
        }
    }

    @Test("GET /health returns JSON when Accept header is application/json")
    func healthReturnsJSONWhenAcceptIsJSON() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "application/json"]
            )
            #expect(response.headers[.contentType] == "application/json")
            let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
            #expect(json["status"] as? String == "ok")
        }
    }

    @Test("GET /health returns JSON when Accept header is wildcard")
    func healthReturnsJSONWhenAcceptIsWildcard() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "*/*"]
            )
            #expect(response.headers[.contentType] == "application/json")
        }
    }

    @Test("GET /health returns JSON when no Accept header is present")
    func healthReturnsJSONWhenNoAcceptHeader() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            #expect(response.headers[.contentType] == "application/json")
        }
    }

    @Test("GET /health HTML response contains status ok")
    func healthHTMLResponseContainsStatusOk() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html"]
            )
            let body = String(buffer: response.body)
            #expect(body.contains("OK"))
        }
    }

    @Test("GET /health HTML response shows MCP bridge disabled")
    func healthHTMLResponseShowsBridgeDisabled() async throws {
        let harness = ServerTestHarness(bridgeHolder: MCPBridgeHolder())
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html"]
            )
            let body = String(buffer: response.body)
            #expect(body.contains("Disabled"))
        }
    }

    @Test("GET /health HTML response shows MCP bridge enabled")
    func healthHTMLResponseShowsBridgeEnabled() async throws {
        let harness = ServerTestHarness(bridgeHolder: MCPBridgeHolder(MockMCPBridgeService()))
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html"]
            )
            let body = String(buffer: response.body)
            #expect(body.contains("Enabled"))
        }
    }

    @Test("GET /health HTML response includes CORS header")
    func healthHTMLResponseIncludesCORSHeader() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.accept: "text/html"]
            )
            #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
        }
    }
}