import Foundation

public struct CopilotRequestHeaders: CopilotRequestHeadersProtocol {
    private let editorVersion: String
    private let plugginVersion: String

    public init(editorVersion: String, plugginVersion: String = CopilotConstants.plugginVersion) {
        self.editorVersion = editorVersion
        self.plugginVersion = plugginVersion
    }

    public func standard(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "X-Request-Id": UUID().uuidString,
            "Openai-Organization": "github-copilot",
            "Editor-Version": editorVersion,
            "Editor-Plugin-Version": plugginVersion,
            "Copilot-Integration-Id": "vscode-chat"
        ]
    }

    public func streaming(token: String) -> [String: String] {
        var headers = standard(token: token)
        headers["Accept"] = "text/event-stream"
        headers["Openai-Intent"] = "conversation-panel"
        return headers
    }

    public func tokenRequest(githubToken: String) -> [String: String] {
        [
            "Authorization": "token \(githubToken)",
            "Accept": "application/json",
            "Editor-Version": editorVersion,
            "Editor-Plugin-Version": plugginVersion
        ]
    }
}
