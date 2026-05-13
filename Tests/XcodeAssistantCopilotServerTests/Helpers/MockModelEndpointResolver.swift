@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockModelEndpointResolver: ModelEndpointResolverProtocol, Sendable {
    private struct State {
        var endpoint: ModelEndpoint = .chatCompletions
        var contextWindow: Int?
        var resolvedModels: [String] = []
        var reasoningSupport: [String: Bool] = [:]
    }

    private let mutex = Mutex(State())

    var endpoint: ModelEndpoint {
        get { mutex.withLock { $0.endpoint } }
        set { mutex.withLock { $0.endpoint = newValue } }
    }

    var contextWindow: Int? {
        get { mutex.withLock { $0.contextWindow } }
        set { mutex.withLock { $0.contextWindow = newValue } }
    }

    func contextWindowTokenLimit(for modelId: String, credentials: CopilotCredentials) async -> Int? {
        mutex.withLock { $0.contextWindow }
    }

    var resolvedModels: [String] { mutex.withLock { $0.resolvedModels } }

    var reasoningSupportByModel: [String: Bool] {
        get { mutex.withLock { $0.reasoningSupport } }
        set { mutex.withLock { $0.reasoningSupport = newValue } }
    }

    func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint {
        mutex.withLock {
            $0.resolvedModels.append(modelId)
            return $0.endpoint
        }
    }

    func supportsReasoningEffort(for modelId: String, credentials: CopilotCredentials) async -> Bool {
        mutex.withLock {
            if let supported = $0.reasoningSupport[modelId], !supported {
                return false
            }
            return true
        }
    }
}
