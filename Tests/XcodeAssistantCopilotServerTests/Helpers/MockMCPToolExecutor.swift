@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockMCPToolExecutor: MCPToolExecutorProtocol, Sendable {
    private struct State {
        var results: [String: String] = [:]
        var errors: [String: Error] = [:]
        var executedTools: [(toolCall: ToolCall, serverName: String)] = []
    }

    private let state = Mutex(State())

    var executedTools: [(toolCall: ToolCall, serverName: String)] {
        state.withLock { $0.executedTools }
    }

    func setResult(_ result: String, for toolName: String) {
        state.withLock { $0.results[toolName] = result }
    }

    func setError(_ error: Error, for toolName: String) {
        state.withLock { $0.errors[toolName] = error }
    }

    func execute(toolCall: ToolCall, serverName: String) async throws -> String {
        state.withLock { $0.executedTools.append((toolCall: toolCall, serverName: serverName)) }
        let toolName = toolCall.function.name ?? ""
        if let error = state.withLock({ $0.errors[toolName] }) {
            throw error
        }
        if let result = state.withLock({ $0.results[toolName] }) {
            return result
        }
        return "Mock result for \(toolName)"
    }
}