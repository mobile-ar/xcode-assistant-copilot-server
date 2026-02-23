import Hummingbird
import HTTPTypes

struct CORSMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    let logger: LoggerProtocol

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        if request.method == .options {
            return Response(
                status: .noContent,
                headers: corsHeaders()
            )
        }

        var response = try await next(request, context)
        let headers = corsHeaders()
        for header in headers {
            response.headers.append(header)
        }
        return response
    }

    private func corsHeaders() -> HTTPFields {
        var headers = HTTPFields()
        headers[HTTPField.Name("Access-Control-Allow-Origin")!] = "*"
        headers[HTTPField.Name("Access-Control-Allow-Methods")!] = "GET, POST, OPTIONS"
        headers[HTTPField.Name("Access-Control-Allow-Headers")!] = "Content-Type, Authorization"
        return headers
    }
}