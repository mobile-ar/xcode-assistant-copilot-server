@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockReasoningEffortResolver: ReasoningEffortResolverProtocol, Sendable {
    private struct State {
        var resolvedEffort: ReasoningEffort?
        var resolvedModels: [String] = []
        var recordedMaxEfforts: [(effort: ReasoningEffort, modelId: String)] = []
        var unsupportedModels: Set<String> = []
    }

    private let state = Mutex(State())

    var resolvedEffort: ReasoningEffort? {
        get { state.withLock { $0.resolvedEffort } }
        set { state.withLock { $0.resolvedEffort = newValue } }
    }

    var resolvedModels: [String] { state.withLock { $0.resolvedModels } }
    var recordedMaxEfforts: [(effort: ReasoningEffort, modelId: String)] { state.withLock { $0.recordedMaxEfforts } }
    var recordedUnsupportedModels: Set<String> { state.withLock { $0.unsupportedModels } }

    func resolve(configured: ReasoningEffort, for modelId: String) async -> ReasoningEffort? {
        state.withLock {
            $0.resolvedModels.append(modelId)
            if $0.unsupportedModels.contains(modelId) {
                return nil
            }
            return $0.resolvedEffort ?? configured
        }
    }

    func recordMaxEffort(_ effort: ReasoningEffort, for modelId: String) async {
        state.withLock { $0.recordedMaxEfforts.append((effort: effort, modelId: modelId)) }
    }

    func recordUnsupported(for modelId: String) async {
        state.withLock { $0.unsupportedModels.insert(modelId) }
    }

    func setUnsupported(_ modelId: String) {
        state.withLock { $0.unsupportedModels.insert(modelId) }
    }
}
