import Foundation

public struct MCPSSEMessageEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String
    public let path: String = ""
    public let headers: [String: String]
    public let body: Data?
    public let timeoutInterval: TimeInterval

    public init(
        messagesURL: String,
        requestData: Data,
        extraHeaders: [String: String],
        timeoutInterval: TimeInterval = 60
    ) {
        self.baseURL = messagesURL
        self.body = requestData
        self.timeoutInterval = timeoutInterval

        var headers: [String: String] = ["Content-Type": "application/json"]
        for (key, value) in extraHeaders {
            headers[key] = value
        }
        self.headers = headers
    }
}
