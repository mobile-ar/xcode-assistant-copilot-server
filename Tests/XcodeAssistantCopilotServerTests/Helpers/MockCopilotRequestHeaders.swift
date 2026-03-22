@testable import XcodeAssistantCopilotServer

struct MockCopilotRequestHeaders: CopilotRequestHeadersProtocol {

    func standard(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json"
        ]
    }

    func streaming(token: String) -> [String: String] {
        var headers = standard(token: token)
        headers["Accept"] = "text/event-stream"
        return headers
    }

    func tokenRequest(githubToken: String) -> [String: String] {
        [
            "Authorization": "token \(githubToken)",
            "Accept": "application/json"
        ]
    }
}