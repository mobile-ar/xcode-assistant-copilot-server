import Foundation

public struct MCPHTTPTerminateEndpoint: Endpoint {
    public let method: HTTPMethod = .delete
    public let baseURL: String
    public let path: String = ""
    public let headers: [String: String]
    public let body: Data? = nil
    public let timeoutInterval: TimeInterval = 30

    public init(serverURL: String, sessionID: String, extraHeaders: [String: String]) {
        self.baseURL = serverURL

        var headers: [String: String] = ["Mcp-Session-Id": sessionID]
        for (key, value) in extraHeaders {
            headers[key] = value
        }
        self.headers = headers
    }
}
