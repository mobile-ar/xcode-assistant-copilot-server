import Hummingbird
import HTTPTypes

struct RequestLoggingMiddleware: RouterMiddleware {
    let logger: LoggerProtocol

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        let method = request.method.rawValue
        let path = request.uri.path
        let start = ContinuousClock.now

        do {
            let response = try await next(request, context)
            let duration = ContinuousClock.now - start
            let statusCode = response.status.code
            logger.info("\(method) \(path) \(statusCode) \(formatted(duration))")
            return response
        } catch {
            let duration = ContinuousClock.now - start
            let statusCode = (error as? HTTPError)?.status.code ?? 500
            logger.info("\(method) \(path) \(statusCode) \(formatted(duration))")
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
