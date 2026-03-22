import Foundation

public struct ResponsesStreamEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String
    public let path = "/responses"
    public let headers: [String: String]
    public let body: Data?
    public let timeoutInterval: TimeInterval

    public init(request: ResponsesAPIRequest, credentials: CopilotCredentials, requestHeaders: CopilotRequestHeadersProtocol, timeoutInterval: TimeInterval = 300) throws {
        self.baseURL = credentials.apiEndpoint
        self.headers = requestHeaders.streaming(token: credentials.token)
        self.body = try JSONEncoder().encode(request)
        self.timeoutInterval = timeoutInterval
    }
}