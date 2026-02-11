import Hummingbird
import HTTPTypes

public struct XcodeUserAgentMiddleware: RouterMiddleware {
    public typealias Context = AppRequestContext

    private let logger: LoggerProtocol

    public init(logger: LoggerProtocol) {
        self.logger = logger
    }

    public func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        let userAgent = request.headers[.userAgent] ?? ""

        guard userAgent.hasPrefix("Xcode/") else {
            logger.warn("Rejected request from unexpected user-agent: \(userAgent)")
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .forbidden,
                headers: headers,
                body: .init(byteBuffer: .init(string: "{\"error\":\"Forbidden\"}\n"))
            )
        }

        return try await next(request, context)
    }
}