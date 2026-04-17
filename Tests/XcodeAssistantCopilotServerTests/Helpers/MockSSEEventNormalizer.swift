@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockSSEEventNormalizer: SSEEventNormalizerProtocol, Sendable {
    private struct State {
        var normalizeCallCount = 0
        var lastInput: String?
    }

    private let state = Mutex(State())

    var normalizeCallCount: Int { state.withLock { $0.normalizeCallCount } }
    var lastInput: String? { state.withLock { $0.lastInput } }

    func normalizeEventData(_ data: String) -> String {
        state.withLock {
            $0.normalizeCallCount += 1
            $0.lastInput = data
        }
        return data
    }
}