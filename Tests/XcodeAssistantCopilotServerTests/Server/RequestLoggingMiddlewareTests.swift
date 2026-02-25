@testable import XcodeAssistantCopilotServer
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Testing

private func buildApp(logger: MockLogger) -> some ApplicationProtocol {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        RequestLoggingMiddleware(logger: logger)
    }
    router.get("health") { _, _ in
        Response(status: .ok)
    }
    router.post("v1/chat/completions") { _, _ in
        Response(status: .ok)
    }
    router.get("v1/models") { _, _ in
        Response(status: .notFound)
    }
    router.get("forbidden") { _, _ in
        Response(status: .forbidden)
    }
    router.get("error") { _, _ -> Response in
        throw HTTPError(.internalServerError)
    }
    return Application(router: router)
}

@Test func logsMethodPathStatusCodeAndDuration() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        #expect(response.status == .ok)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.hasPrefix("GET /health 200 "))
        #expect(message.contains("ms") || message.contains("s"))
    }
}

@Test func logsPostMethod() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .post)
        #expect(response.status == .ok)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.infoMessages[0].hasPrefix("POST /v1/chat/completions 200 "))
    }
}

@Test func logsNonSuccessStatusCodes() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/models", method: .get)
        #expect(response.status == .notFound)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.infoMessages[0].hasPrefix("GET /v1/models 404 "))
    }
}

@Test func logsForbiddenStatusCode() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/forbidden", method: .get)
        #expect(response.status == .forbidden)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.infoMessages[0].hasPrefix("GET /forbidden 403 "))
    }
}

@Test func logsWhenHandlerThrows() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/error", method: .get)
        #expect(response.status == .internalServerError)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.infoMessages[0].hasPrefix("GET /error 500 "))
    }
}

@Test func respectsLogLevelByUsingInfoLevel() async throws {
    let logger = MockLogger(level: .all)
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        _ = try await client.execute(uri: "/health", method: .get)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.debugMessages.isEmpty)
        #expect(logger.errorMessages.isEmpty)
        #expect(logger.warnMessages.isEmpty)
    }
}

@Test func logsDurationInMillisecondsForFastRequests() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        _ = try await client.execute(uri: "/health", method: .get)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.hasSuffix("ms"))
    }
}

@Test func logsEachRequestSeparately() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        _ = try await client.execute(uri: "/health", method: .get)
        _ = try await client.execute(uri: "/v1/chat/completions", method: .post)

        #expect(logger.infoMessages.count == 2)
        #expect(logger.infoMessages[0].hasPrefix("GET /health 200 "))
        #expect(logger.infoMessages[1].hasPrefix("POST /v1/chat/completions 200 "))
    }
}

@Test func logsUnknownRouteAs404() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/nonexistent", method: .get)
        #expect(response.status == .notFound)
        #expect(logger.infoMessages.count == 1)
        #expect(logger.infoMessages[0].hasPrefix("GET /nonexistent 404 "))
    }
}