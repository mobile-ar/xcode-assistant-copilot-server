import Foundation

public protocol CopilotRequestHeadersProtocol: Sendable {
    func standard(token: String) -> [String: String]
    func streaming(token: String) -> [String: String]
    func tokenRequest(githubToken: String) -> [String: String]
}