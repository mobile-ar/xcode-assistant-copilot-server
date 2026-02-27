@testable import XcodeAssistantCopilotServer
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Testing

private func buildApp(logger: MockLogger = MockLogger()) -> some ApplicationProtocol {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        CORSMiddleware(logger: logger)
    }
    router.get("health") { _, _ in
        Response(status: .ok, headers: [:], body: .init(byteBuffer: .init(string: "OK")))
    }
    router.post("v1/chat/completions") { _, _ in
        Response(status: .ok, headers: [:], body: .init(byteBuffer: .init(string: "{}")))
    }
    return Application(router: router)
}

@Test func optionsReturns204() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .options)
        #expect(response.status == .noContent)
    }
}

@Test func optionsResponseContainsAllowOriginHeader() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .options)
        let allowOrigin = response.headers[HTTPField.Name("Access-Control-Allow-Origin")!]
        #expect(allowOrigin == "*")
    }
}

@Test func optionsResponseContainsAllowMethodsHeader() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .options)
        let allowMethods = response.headers[HTTPField.Name("Access-Control-Allow-Methods")!]
        #expect(allowMethods == "GET, POST, OPTIONS")
    }
}

@Test func optionsResponseContainsAllowHeadersHeader() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .options)
        let allowHeaders = response.headers[HTTPField.Name("Access-Control-Allow-Headers")!]
        #expect(allowHeaders == "Content-Type, Authorization")
    }
}

@Test func optionsResponseHasNoBody() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .options)
        #expect(response.status == .noContent)
        let body = String(buffer: response.body)
        #expect(body.isEmpty)
    }
}

@Test func getResponseContainsCORSHeaders() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        #expect(response.status == .ok)

        let allowOrigin = response.headers[HTTPField.Name("Access-Control-Allow-Origin")!]
        #expect(allowOrigin == "*")

        let allowMethods = response.headers[HTTPField.Name("Access-Control-Allow-Methods")!]
        #expect(allowMethods == "GET, POST, OPTIONS")

        let allowHeaders = response.headers[HTTPField.Name("Access-Control-Allow-Headers")!]
        #expect(allowHeaders == "Content-Type, Authorization")
    }
}

@Test func postResponseContainsCORSHeaders() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/v1/chat/completions", method: .post)
        #expect(response.status == .ok)

        let allowOrigin = response.headers[HTTPField.Name("Access-Control-Allow-Origin")!]
        #expect(allowOrigin == "*")
    }
}

@Test func getResponsePreservesOriginalBody() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/health", method: .get)
        #expect(response.status == .ok)
        let body = String(buffer: response.body)
        #expect(body == "OK")
    }
}

@Test func optionsOnUnknownRouteStillReturns204WithCORSHeaders() async throws {
    let app = buildApp()

    try await app.test(.router) { client in
        let response = try await client.execute(uri: "/nonexistent", method: .options)
        #expect(response.status == .noContent)

        let allowOrigin = response.headers[HTTPField.Name("Access-Control-Allow-Origin")!]
        #expect(allowOrigin == "*")
    }
}