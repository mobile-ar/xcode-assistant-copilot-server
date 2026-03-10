@testable import XcodeAssistantCopilotServer

final class MockAgentStreamWriter: AgentStreamWriterProtocol, @unchecked Sendable {
    private(set) var roleDeltaWritten = false
    private(set) var progressTexts: [String] = []
    private(set) var finalContent: String?
    private(set) var finalToolCalls: [ToolCall]?
    private(set) var finalHadToolUse: Bool?
    private(set) var finishCalled = false

    func writeRoleDelta() {
        roleDeltaWritten = true
    }

    func writeProgressText(_ text: String) {
        progressTexts.append(text)
    }

    func writeFinalContent(_ text: String, toolCalls: [ToolCall]?, hadToolUse: Bool) {
        finalContent = text
        finalToolCalls = toolCalls
        finalHadToolUse = hadToolUse
    }

    func finish() {
        finishCalled = true
    }

    var allProgressText: String {
        progressTexts.joined()
    }
}