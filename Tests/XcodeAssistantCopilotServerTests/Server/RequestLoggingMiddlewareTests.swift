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

private func extractRequestID(from message: String) -> String? {
    guard message.hasPrefix("["),
          let closingBracket = message.firstIndex(of: "]") else {
        return nil
    }
    let start = message.index(after: message.startIndex)
    return String(message[start..<closingBracket])
}

private func isValidUUID(_ string: String) -> Bool {
    let parts = string.split(separator: "-")
    guard parts.count == 5 else { return false }
    let expectedLengths = [8, 4, 4, 4, 12]
    for (part, length) in zip(parts, expectedLengths) {
        guard part.count == length,
              part.allSatisfy({ $0.isHexDigit }) else {
            return false
        }
    }
    return true
}

@Test func logsMethodPathStatusCodeAndDurationWithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        #expect(response.status == .ok)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
        #expect(message.contains("GET /health 200 "))
        #expect(message.contains("ms") || message.contains("s"))
    }
}

@Test func logsPostMethodWithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .post)
        #expect(response.status == .ok)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.contains("POST /v1/chat/completions 200 "))
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
    }
}

@Test func logsNonSuccessStatusCodesWithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/models", method: .get)
        #expect(response.status == .notFound)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.contains("GET /v1/models 404 "))
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
    }
}

@Test func logsForbiddenStatusCodeWithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/forbidden", method: .get)
        #expect(response.status == .forbidden)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.contains("GET /forbidden 403 "))
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
    }
}

@Test func logsWhenHandlerThrowsWithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/error", method: .get)
        #expect(response.status == .internalServerError)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.contains("GET /error 500 "))
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
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

@Test func logsEachRequestWithUniqueRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        _ = try await client.execute(uri: "/health", method: .get)
        _ = try await client.execute(uri: "/v1/chat/completions", method: .post)

        #expect(logger.infoMessages.count == 2)
        let id1 = extractRequestID(from: logger.infoMessages[0])
        let id2 = extractRequestID(from: logger.infoMessages[1])
        #expect(id1 != nil)
        #expect(id2 != nil)
        #expect(id1 != id2)
        #expect(logger.infoMessages[0].contains("GET /health 200 "))
        #expect(logger.infoMessages[1].contains("POST /v1/chat/completions 200 "))
    }
}

@Test func logsUnknownRouteAs404WithRequestID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/nonexistent", method: .get)
        #expect(response.status == .notFound)
        #expect(logger.infoMessages.count == 1)
        let message = logger.infoMessages[0]
        #expect(message.contains("GET /nonexistent 404 "))
        let requestID = extractRequestID(from: message)
        #expect(requestID != nil)
        #expect(isValidUUID(requestID!))
    }
}

@Test func responseIncludesRequestIDHeader() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        let headerValue = response.headers[HTTPField.Name("X-Request-Id")!]
        #expect(headerValue != nil)
        #expect(isValidUUID(headerValue!))
    }
}

@Test func responseRequestIDHeaderMatchesLoggedID() async throws {
    let logger = MockLogger()
    let app = buildApp(logger: logger)

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        let headerValue = response.headers[HTTPField.Name("X-Request-Id")!]
        let loggedID = extractRequestID(from: logger.infoMessages[0])
        #expect(headerValue == loggedID)
    }
}