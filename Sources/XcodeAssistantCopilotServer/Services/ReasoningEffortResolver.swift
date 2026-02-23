public protocol ReasoningEffortResolverProtocol: Sendable {
    func resolve(configured: ReasoningEffort, for modelId: String) async -> ReasoningEffort
    func recordMaxEffort(_ effort: ReasoningEffort, for modelId: String) async
}

public actor ReasoningEffortResolver: ReasoningEffortResolverProtocol {
    private var cachedMaxEffort: [String: ReasoningEffort] = [:]

    public init() {}

    public func resolve(configured: ReasoningEffort, for modelId: String) -> ReasoningEffort {
        guard let cached = cachedMaxEffort[modelId] else {
            return configured
        }
        return min(configured, cached)
    }

    public func recordMaxEffort(_ effort: ReasoningEffort, for modelId: String) {
        cachedMaxEffort[modelId] = effort
    }
}