@testable import XcodeAssistantCopilotServer

final class MockReasoningEffortResolver: ReasoningEffortResolverProtocol, @unchecked Sendable {
    var resolvedEffort: ReasoningEffort?
    private(set) var resolvedModels: [String] = []
    private(set) var recordedMaxEfforts: [(effort: ReasoningEffort, modelId: String)] = []

    func resolve(configured: ReasoningEffort, for modelId: String) async -> ReasoningEffort {
        resolvedModels.append(modelId)
        return resolvedEffort ?? configured
    }

    func recordMaxEffort(_ effort: ReasoningEffort, for modelId: String) async {
        recordedMaxEfforts.append((effort: effort, modelId: modelId))
    }
}