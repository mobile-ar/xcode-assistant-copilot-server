import Foundation

public struct MCPHTTPRequestEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String
    public let path: String = ""
    public let headers: [String: String]
    public let body: Data?
    public let timeoutInterval: TimeInterval

    public init(
        serverURL: String,
        requestData: Data,
        sessionID: String?,
        extraHeaders: [String: String],
        timeoutInterval: TimeInterval = 60
    ) {
        self.baseURL = serverURL
        self.body = requestData
        self.timeoutInterval = timeoutInterval

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        ]
        for (key, value) in extraHeaders {
            headers[key] = value
        }
        if let sessionID {
            headers["Mcp-Session-Id"] = sessionID
        }
        self.headers = headers
    }
}
