import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

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

    public func handle(request: Request, context: some RequestContext) async throws -> Response {
        let credentials: CopilotCredentials
        do {
            credentials = try await authService.getValidCopilotToken()
        } catch {
            logger.error("Authentication failed: \(error)")
            return errorResponse(
                status: .unauthorized,
                message: "Authentication failed: \(error)"
            )
        }

        let models: [CopilotModel]
        do {
            models = try await copilotAPI.listModels(credentials: credentials)
        } catch {
            logger.error("Failed to fetch models: \(error)")
            return errorResponse(
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
            return errorResponse(
                status: .internalServerError,
                message: "Failed to encode response"
            )
        }
    }

    private func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
        let body: [String: [String: String]] = [
            "error": [
                "message": message,
                "type": "api_error",
            ],
        ]

        let data = (try? JSONEncoder().encode(body)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}