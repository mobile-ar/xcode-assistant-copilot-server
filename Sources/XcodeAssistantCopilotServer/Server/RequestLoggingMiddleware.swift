import Hummingbird
import HTTPTypes

struct RequestLoggingMiddleware: RouterMiddleware {
    let logger: LoggerProtocol

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        let requestID = context.requestID
        let method = request.method.rawValue
        let path = request.uri.path
        let start = ContinuousClock.now

        do {
            var response = try await next(request, context)
            let duration = ContinuousClock.now - start
            let statusCode = response.status.code
            logger.info("[\(requestID)] \(method) \(path) \(statusCode) \(formatted(duration))")
            response.headers[HTTPField.Name("X-Request-Id")!] = requestID
            return response
        } catch {
            let duration = ContinuousClock.now - start
            let statusCode = (error as? HTTPError)?.status.code ?? 500
            logger.info("[\(requestID)] \(method) \(path) \(statusCode) \(formatted(duration))")
            throw error
        }
    }

    private func formatted(_ duration: Duration) -> String {
        let milliseconds = duration.components.seconds * 1000
            + duration.components.attoseconds / 1_000_000_000_000_000
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }
}
