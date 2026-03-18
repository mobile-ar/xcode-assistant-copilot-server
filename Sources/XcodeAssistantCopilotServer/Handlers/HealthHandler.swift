import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct HealthHandler: Sendable {
    private let bridgeHolder: MCPBridgeHolder
    private let logger: LoggerProtocol
    private let startTime: Date

    public init(
        bridgeHolder: MCPBridgeHolder,
        logger: LoggerProtocol,
        startTime: Date = Date()
    ) {
        self.bridgeHolder = bridgeHolder
        self.logger = logger
        self.startTime = startTime
    }

    public func buildHealthResponse() async -> HealthResponse {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))
        let isEnabled = await bridgeHolder.bridge != nil
        let mcpBridgeStatus = MCPBridgeStatus(enabled: isEnabled)
        return HealthResponse(
            status: "ok",
            uptimeSeconds: uptimeSeconds,
            mcpBridge: mcpBridgeStatus
        )
    }

    public func handle() async throws -> Response {
        let healthResponse = await buildHealthResponse()

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
