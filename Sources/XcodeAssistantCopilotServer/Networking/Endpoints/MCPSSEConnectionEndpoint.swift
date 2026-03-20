import Foundation

public struct MCPSSEConnectionEndpoint: Endpoint {
    public let method: HTTPMethod = .get
    public let baseURL: String
    public let path: String = ""
    public let headers: [String: String]
    public let body: Data? = nil
    public let timeoutInterval: TimeInterval

    public init(serverURL: String, extraHeaders: [String: String], timeoutInterval: TimeInterval = 300) {
        self.baseURL = serverURL
        self.timeoutInterval = timeoutInterval

        var headers: [String: String] = ["Accept": "text/event-stream"]
        for (key, value) in extraHeaders {
            headers[key] = value
        }
        self.headers = headers
    }
}
