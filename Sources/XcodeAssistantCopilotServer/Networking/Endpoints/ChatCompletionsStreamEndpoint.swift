import Foundation

public struct ChatCompletionsStreamEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String
    public let path = "/chat/completions"
    public let headers: [String: String]
    public let body: Data?
    public let timeoutInterval: TimeInterval = 300

    public init(request: CopilotChatRequest, credentials: CopilotCredentials) throws {
        self.baseURL = credentials.apiEndpoint
        self.headers = CopilotRequestHeaders.streaming(token: credentials.token)
        self.body = try JSONEncoder().encode(request)
    }
}