import Foundation

public enum ModelEndpoint: Sendable, Equatable {
    case chatCompletions
    case responses
}

public protocol ModelEndpointResolverProtocol: Sendable {
    func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint
}

public actor ModelEndpointResolver: ModelEndpointResolverProtocol {
    private let copilotAPI: CopilotAPIServiceProtocol
    private let logger: LoggerProtocol
    private var cachedEndpoints: [String: [String]]?
    private var lastFetchTime: Date?
    private static let cacheDuration: TimeInterval = 300

    public init(copilotAPI: CopilotAPIServiceProtocol, logger: LoggerProtocol) {
        self.copilotAPI = copilotAPI
        self.logger = logger
    }

    public func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint {
        await refreshCacheIfNeeded(credentials: credentials)

        guard let endpoints = cachedEndpoints?[modelId] else {
            return .chatCompletions
        }

        if endpoints.contains("/responses") && !endpoints.contains("/chat/completions") {
            return .responses
        }

        return .chatCompletions
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
            for model in models {
                if let supported = model.supportedEndpoints {
                    mapping[model.id] = supported
                }
            }
            cachedEndpoints = mapping
            lastFetchTime = .now
            logger.debug("Refreshed model endpoint cache with \(models.count) model(s)")
        } catch {
            logger.warn("Failed to refresh model endpoint cache: \(error)")
        }
    }
}