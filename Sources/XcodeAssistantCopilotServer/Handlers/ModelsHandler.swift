import Foundation
import Hummingbird
import HTTPTypes

public struct ModelsHandler: Sendable {
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let logger: LoggerProtocol

    public init(
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        logger: LoggerProtocol
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.logger = logger
    }

    public func handle() async throws -> Response {
        let credentials: CopilotCredentials
        do {
            credentials = try await authService.getValidCopilotToken()
        } catch {
            logger.error("Authentication failed: \(error)")
            return ErrorResponseBuilder.build(
                status: .unauthorized,
                message: "Authentication failed: \(error)"
            )
        }

        return await buildModelsResponse(credentials: credentials)
    }

    func buildModelsResponse(credentials: CopilotCredentials) async -> Response {
        let models: [CopilotModel]
        do {
            models = try await fetchModelsWithRetry(credentials: credentials)
        } catch {
            logger.error("Failed to fetch models: \(error)")
            return ErrorResponseBuilder.build(
                status: .internalServerError,
                message: "Failed to list models"
            )
        }

        let modelObjects = models.map { model in
            ModelObject(id: model.id)
        }

        let modelsResponse = ModelsResponse(data: modelObjects)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(modelsResponse)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        } catch {
            logger.error("Failed to encode models response: \(error)")
            return ErrorResponseBuilder.build(
                status: .internalServerError,
                message: "Failed to encode response"
            )
        }
    }

    private func fetchModelsWithRetry(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        try await authService.retryingOnUnauthorized(credentials: credentials) { newCredentials in
            try await copilotAPI.listModels(credentials: newCredentials)
        }
    }
}
