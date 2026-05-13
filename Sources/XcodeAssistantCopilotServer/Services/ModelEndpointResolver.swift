import Foundation

public enum ModelEndpoint: Sendable, Equatable {
    case chatCompletions
    case responses
}

public protocol ModelEndpointResolverProtocol: Sendable {
    func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint
    func contextWindowTokenLimit(for modelId: String, credentials: CopilotCredentials) async -> Int?
    func supportsReasoningEffort(for modelId: String, credentials: CopilotCredentials) async -> Bool
}

public actor ModelEndpointResolver: ModelEndpointResolverProtocol {
    private let copilotAPI: CopilotAPIServiceProtocol
    private let logger: LoggerProtocol
    private var cachedEndpoints: [String: [String]]?
    private var cachedContextWindows: [String: Int]?
    private var cachedReasoningSupport: [String: Bool]?
    private var lastFetchTime: Date?
    private static let cacheDuration: TimeInterval = 300

    public init(copilotAPI: CopilotAPIServiceProtocol, logger: LoggerProtocol) {
        self.copilotAPI = copilotAPI
        self.logger = logger
    }

    public func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint {
        await refreshCacheIfNeeded(credentials: credentials)

        guard let endpoints = cachedEndpoints?[modelId] else {
            logger.info("Model '\(modelId)' not found in endpoint cache (\(cachedEndpoints?.count ?? 0) cached model(s)), defaulting to chatCompletions")
            if let cached = cachedEndpoints {
                logger.debug("Cached model IDs: \(cached.keys.sorted().joined(separator: ", "))")
            }
            return .chatCompletions
        }

        logger.info("Model '\(modelId)' supported endpoints: \(endpoints.joined(separator: ", "))")

        if endpoints.contains("/responses") && !endpoints.contains("/chat/completions") {
            logger.info("Resolved endpoint for '\(modelId)': responses (responses-only model)")
            return .responses
        }

        logger.info("Resolved endpoint for '\(modelId)': chatCompletions")
        return .chatCompletions
    }

    public func contextWindowTokenLimit(for modelId: String, credentials: CopilotCredentials) async -> Int? {
        await refreshCacheIfNeeded(credentials: credentials)

        guard let tokenLimit = cachedContextWindows?[modelId] else {
            logger.info("No context window token limit found for model '\(modelId)'")
            return nil
        }

        logger.info("Context window token limit for '\(modelId)': \(tokenLimit)")
        return tokenLimit
    }

    public func supportsReasoningEffort(for modelId: String, credentials: CopilotCredentials) async -> Bool {
        await refreshCacheIfNeeded(credentials: credentials)

        guard let supported = cachedReasoningSupport?[modelId] else {
            logger.info("No reasoning effort support info for model '\(modelId)', assuming supported")
            return true
        }

        logger.info("Reasoning effort support for '\(modelId)': \(supported)")
        return supported
    }

    private func refreshCacheIfNeeded(credentials: CopilotCredentials) async {
        if let lastFetch = lastFetchTime,
           Date.now.timeIntervalSince(lastFetch) < Self.cacheDuration,
           cachedEndpoints != nil {
            return
        }

        do {
            let models = try await copilotAPI.listModels(credentials: credentials)
            var mapping: [String: [String]] = [:]
            var contextWindows: [String: Int] = [:]
            var reasoningSupport: [String: Bool] = [:]
            for model in models {
                if let supported = model.supportedEndpoints {
                    mapping[model.id] = supported
                }
                if let maxTokens = model.capabilities?.limits?.maxContextWindowTokens {
                    contextWindows[model.id] = maxTokens
                }
                if let supports = model.capabilities?.supports?.reasoningEffort {
                    reasoningSupport[model.id] = supports
                }
            }
            cachedEndpoints = mapping
            cachedContextWindows = contextWindows
            cachedReasoningSupport = reasoningSupport
            lastFetchTime = .now
            logger.debug("Refreshed model endpoint cache with \(models.count) model(s)")
        } catch {
            logger.warn("Failed to refresh model endpoint cache: \(error)")
        }
    }
}