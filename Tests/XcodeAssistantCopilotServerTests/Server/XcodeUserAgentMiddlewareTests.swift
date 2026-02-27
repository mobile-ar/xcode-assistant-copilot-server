@testable import XcodeAssistantCopilotServer
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Testing

private func buildApp(logger: MockLogger = MockLogger()) -> some ApplicationProtocol {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        XcodeUserAgentMiddleware(logger: logger)
    }
    router.get("health") { _, _ in
        Response(status: .ok)
    }
    router.get("v1/models") { _, _ in
        Response(status: .ok)
    }
    router.post("v1/chat/completions") { _, _ in
        Response(status: .ok)
    }
    return Application(router: router)
}

private func buildAppWithLogger() -> (some ApplicationProtocol, MockLogger) {
    let logger = MockLogger()
    let app = buildApp(logger: logger)
    return (app, logger)
}

@Test func allowsRequestWithXcodeUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "Xcode/16.0"]
        )
        #expect(response.status == .ok)
    }
}

@Test func allowsRequestWithXcodeUserAgentAndBuildNumber() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "Xcode/16.2 (16C5032a)"]
        )
        #expect(response.status == .ok)
    }
}

@Test func rejectsRequestWithNonXcodeUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "curl/8.0"]
        )
        #expect(response.status == .forbidden)
    }
}

@Test func rejectsRequestWithEmptyUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: ""]
        )
        #expect(response.status == .forbidden)
    }
}

@Test func rejectsRequestWithMissingUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get
        )
        #expect(response.status == .forbidden)
    }
}

@Test func rejectsRequestWithXcodeInMiddleOfUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "Mozilla/5.0 Xcode/16.0"]
        )
        #expect(response.status == .forbidden)
    }
}

@Test func rejectsRequestWithLowercaseXcodeUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "xcode/16.0"]
        )
        #expect(response.status == .forbidden)
    }
}

@Test func healthEndpointBypassesUserAgentCheck() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/health",
            method: .get,
            headers: [.userAgent: "curl/8.0"]
        )
        #expect(response.status == .ok)
    }
}

@Test func healthEndpointAllowsNoUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/health",
            method: .get
        )
        #expect(response.status == .ok)
    }
}

@Test func rejectedRequestReturnsJSONErrorBody() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "NotXcode/1.0"]
        )
        #expect(response.status == .forbidden)
        let body = String(buffer: response.body)
        #expect(body.contains("Forbidden"))
    }
}

@Test func rejectedRequestLogsWarning() async throws {
    let (app, logger) = buildAppWithLogger()

    try await app.test(.router) { client in
        _ = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "BadAgent/1.0"]
        )
        #expect(logger.warnMessages.count == 1)
        #expect(logger.warnMessages[0].contains("BadAgent/1.0"))
    }
}

@Test func acceptedRequestDoesNotLogWarning() async throws {
    let (app, logger) = buildAppWithLogger()

    try await app.test(.router) { client in
        _ = try await client.execute(
            uri: "/v1/models",
            method: .get,
            headers: [.userAgent: "Xcode/16.0"]
        )
        #expect(logger.warnMessages.isEmpty)
    }
}

@Test func allowsPostRequestWithXcodeUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/chat/completions",
            method: .post,
            headers: [.userAgent: "Xcode/16.0"]
        )
        #expect(response.status == .ok)
    }
}

@Test func rejectsPostRequestWithoutXcodeUserAgent() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/v1/chat/completions",
            method: .post,
            headers: [.userAgent: "PostmanRuntime/7.0"]
        )
        #expect(response.status == .forbidden)
    }
}