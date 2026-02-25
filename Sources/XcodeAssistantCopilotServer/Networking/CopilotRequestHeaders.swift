import Foundation

public enum CopilotRequestHeaders {

    public static func standard(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "X-Request-Id": UUID().uuidString,
            "Openai-Organization": "github-copilot",
            "Editor-Version": "Xcode/26.0",
            "Editor-Plugin-Version": "copilot-xcode/0.1.0",
            "Copilot-Integration-Id": "vscode-chat"
        ]
    }

    public static func streaming(token: String) -> [String: String] {
        var headers = standard(token: token)
        headers["Accept"] = "text/event-stream"
        headers["Openai-Intent"] = "conversation-panel"
        return headers
    }
}