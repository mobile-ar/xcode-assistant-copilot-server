import Foundation

public struct CopilotTokenEndpoint: Endpoint {
    public let method: HTTPMethod = .get
    public let baseURL: String = "https://api.github.com"
    public let path: String = "/copilot_internal/v2/token"
    public let headers: [String: String]

    public init(githubToken: String) {
        self.headers = [
            "Authorization": "token \(githubToken)",
            "Accept": "application/json",
            "Editor-Version": "Xcode/26.0",
            "Editor-Plugin-Version": "copilot-xcode/0.1.0"
        ]
    }
}