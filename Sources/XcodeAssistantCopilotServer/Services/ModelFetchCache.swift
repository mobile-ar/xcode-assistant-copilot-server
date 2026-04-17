import Foundation

public actor ModelFetchCache {
    public private(set) var lastFetchTime: Date?
    private var cachedModels: [CopilotModel]?

    public init() {}

    public func recordFetch(models: [CopilotModel]) {
        lastFetchTime = .now
        cachedModels = models
    }

    public func cachedModelsIfValid(ttl: TimeInterval) -> [CopilotModel]? {
        guard let lastFetchTime, let cachedModels else { return nil }
        let age = Date.now.timeIntervalSince(lastFetchTime)
        guard age < ttl else { return nil }
        return cachedModels
    }
}
