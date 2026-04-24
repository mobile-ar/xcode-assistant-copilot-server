@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockConsolePrompter: ConsolePrompterProtocol, Sendable {
    private struct State {
        var prompts: [String] = []
    }

    private let state = Mutex(State())
    private let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    var prompts: [String] { state.withLock { $0.prompts } }

    func promptYesNo(_ message: String) -> Bool {
        state.withLock { $0.prompts.append(message) }
        return answer
    }
}