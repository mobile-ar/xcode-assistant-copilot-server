import Foundation

public struct CopilotTokenEndpoint: Endpoint {
    public let method: HTTPMethod = .get
    public let baseURL: String = "https://api.github.com"
    public let path: String = "/copilot_internal/v2/token"
    public let headers: [String: String]

    public init(githubToken: String, requestHeaders: CopilotRequestHeadersProtocol) {
        self.headers = requestHeaders.tokenRequest(githubToken: githubToken)
    }
}