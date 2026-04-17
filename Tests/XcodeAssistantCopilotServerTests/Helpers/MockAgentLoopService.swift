@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockAgentLoopService: AgentLoopServiceProtocol, Sendable {
    private struct State {
        var runCallCount = 0
        var lastRequest: ChatCompletionRequest?
        var lastCredentials: CopilotCredentials?
        var lastAllTools: [Tool]?
        var lastMcpToolServerMap: [String: String]?
    }

    private let state = Mutex(State())

    var runCallCount: Int { state.withLock { $0.runCallCount } }
    var lastRequest: ChatCompletionRequest? { state.withLock { $0.lastRequest } }

    func runAgentLoop(
        request: ChatCompletionRequest,
        credentials: CopilotCredentials,
        allTools: [Tool],
        mcpToolServerMap: [String: String],
        writer: some AgentStreamWriterProtocol
    ) async {
        state.withLock {
            $0.runCallCount += 1
            $0.lastRequest = request
            $0.lastCredentials = credentials
            $0.lastAllTools = allTools
            $0.lastMcpToolServerMap = mcpToolServerMap
        }
        writer.writeFinalContent("mock response", toolCalls: nil, hadToolUse: false)
        writer.finish()
    }
}