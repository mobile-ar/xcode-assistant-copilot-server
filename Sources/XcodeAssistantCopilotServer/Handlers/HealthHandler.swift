import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct HealthHandler: Sendable {
    private let mcpBridge: MCPBridgeServiceProtocol?
    private let logger: LoggerProtocol
    private let startTime: Date

    public init(
        mcpBridge: MCPBridgeServiceProtocol?,
        logger: LoggerProtocol,
        startTime: Date = Date()
    ) {
        self.mcpBridge = mcpBridge
        self.logger = logger
        self.startTime = startTime
    }

    public func buildHealthResponse() -> HealthResponse {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))
        let mcpBridgeStatus = MCPBridgeStatus(enabled: mcpBridge != nil)
        return HealthResponse(
            status: "ok",
            uptimeSeconds: uptimeSeconds,
            mcpBridge: mcpBridgeStatus
        )
    }

    public func handle(request: Request, context: some RequestContext) async throws -> Response {
        let healthResponse = buildHealthResponse()

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(healthResponse)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        } catch {
            logger.error("Failed to encode health response: \(error)")
            return ErrorResponseBuilder.build(
                status: .internalServerError,
                message: "Failed to encode health response"
            )
        }
    }
}