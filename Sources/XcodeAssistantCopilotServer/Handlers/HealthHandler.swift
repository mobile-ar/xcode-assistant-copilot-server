import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct HealthHandler: Sendable {
    private let bridgeHolder: MCPBridgeHolder
    private let authService: AuthServiceProtocol
    private let modelFetchCache: ModelFetchCache
    private let logger: LoggerProtocol
    private let startTime: Date

    public init(
        bridgeHolder: MCPBridgeHolder,
        authService: AuthServiceProtocol,
        modelFetchCache: ModelFetchCache,
        logger: LoggerProtocol,
        startTime: Date = Date()
    ) {
        self.bridgeHolder = bridgeHolder
        self.authService = authService
        self.modelFetchCache = modelFetchCache
        self.logger = logger
        self.startTime = startTime
    }

    public func buildHealthResponse() async -> HealthResponse {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))

        async let isBridgeEnabled = bridgeHolder.bridge != nil
        async let tokenInfo = authService.cachedTokenInfo()
        async let lastFetchTime = modelFetchCache.lastFetchTime

        let mcpBridgeStatus = await MCPBridgeStatus(enabled: isBridgeEnabled)
        let authentication = buildAuthenticationStatus(from: await tokenInfo)
        let lastModelFetchTime = formatDate(await lastFetchTime)

        return HealthResponse(
            status: "ok",
            uptimeSeconds: uptimeSeconds,
            mcpBridge: mcpBridgeStatus,
            authentication: authentication,
            lastModelFetchTime: lastModelFetchTime
        )
    }

    public func handle(request: Request) async throws -> Response {
        let healthResponse = await buildHealthResponse()        
        if let acceptHeader = request.headers[.accept],
            acceptHeader.contains("text/html") {
            return buildHTMLResponse(healthResponse)
        }
        return buildJSONResponse(healthResponse)
    }

    private func buildHTMLResponse(_ healthResponse: HealthResponse) -> Response {
        let renderer = HealthHTMLRenderer()
        let html = renderer.render(healthResponse)
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(string: html))
        )
    }

    private func buildJSONResponse(_ healthResponse: HealthResponse) -> Response {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(healthResponse)
            data.append(contentsOf: [0x0A])
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

    private func buildAuthenticationStatus(from tokenInfo: CopilotTokenInfo?) -> AuthenticationStatus {
        guard let tokenInfo else {
            return AuthenticationStatus(state: .notConnected, copilotTokenExpiry: nil)
        }
        let expiry = iso8601Formatter().string(from: tokenInfo.expiresAt)
        let state: AuthenticationState = tokenInfo.isAuthenticated ? .authenticated : .tokenExpired
        return AuthenticationStatus(state: state, copilotTokenExpiry: expiry)
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601Formatter().string(from: date)
    }

    private func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
