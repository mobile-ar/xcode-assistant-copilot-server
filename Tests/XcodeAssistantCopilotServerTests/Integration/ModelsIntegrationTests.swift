@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@Suite("Models endpoint integration")
struct ModelsIntegrationTests {

    @Test("GET /v1/models returns 200 when authentication succeeds")
    func modelsReturns200() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.models = [CopilotModel(id: "gpt-4o", supportedEndpoints: ["/chat/completions"])]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            #expect(response.status == .ok)
        }
    }

    @Test("GET /v1/models response body contains the expected data array")
    func modelsResponseContainsDataArray() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.models = [CopilotModel(id: "gpt-4o", supportedEndpoints: ["/chat/completions"])]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            let modelsResponse = try JSONDecoder().decode(
                ModelsResponse.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(modelsResponse.data.count == 1)
            #expect(modelsResponse.data[0].id == "gpt-4o")
        }
    }

    @Test("GET /v1/models returns only chat-usable models")
    func modelsFiltersNonChatModels() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.models = [
            CopilotModel(id: "chat-model", supportedEndpoints: ["/chat/completions"]),
            CopilotModel(id: "embedding-model", supportedEndpoints: ["/embeddings"]),
        ]
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            let modelsResponse = try JSONDecoder().decode(
                ModelsResponse.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(modelsResponse.data.count == 1)
            #expect(modelsResponse.data[0].id == "chat-model")
        }
    }

    @Test("GET /v1/models returns an empty data array when no models are available")
    func modelsReturnsEmptyDataArray() async throws {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.models = []
        let harness = ServerTestHarness(copilotAPI: copilotAPI)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            let modelsResponse = try JSONDecoder().decode(
                ModelsResponse.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(modelsResponse.data.isEmpty)
        }
    }

    @Test("GET /v1/models returns 401 when authentication fails")
    func modelsReturns401WhenAuthFails() async throws {
        let authService = MockAuthService()
        authService.shouldThrow = AuthServiceError.notAuthenticated
        let harness = ServerTestHarness(authService: authService)
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test("GET /v1/models response has application/json content-type")
    func modelsResponseHasJSONContentType() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            #expect(response.headers[.contentType] == "application/json")
        }
    }

    @Test("GET /v1/models response includes CORS allow-origin header")
    func modelsResponseIncludesCORSHeader() async throws {
        let harness = ServerTestHarness()
        let app = harness.makeApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.userAgent: "Xcode/16.0"]
            )
            #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
        }
    }
}