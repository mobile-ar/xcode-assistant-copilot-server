import Foundation

public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let baseDelayMilliseconds: Int

    public static let `default` = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 500)
    public static let disabled = RetryPolicy(maxRetries: 0, baseDelayMilliseconds: 0)

    public init(maxRetries: Int, baseDelayMilliseconds: Int) {
        self.maxRetries = maxRetries
        self.baseDelayMilliseconds = baseDelayMilliseconds
    }

    public func execute<T: Sendable>(
        logger: LoggerProtocol,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let hasRetriesLeft = attempt < maxRetries
                if isRetryable(error), hasRetriesLeft {
                    let delayMs = baseDelayMilliseconds * (1 << attempt)
                    logger.warn("Transient error (attempt \(attempt + 1)/\(maxRetries + 1)), retrying in \(delayMs)ms: \(error)")
                    try await Task.sleep(for: .milliseconds(delayMs))
                } else {
                    throw error
                }
            }
        }
        fatalError("Unreachable: retry loop completed without returning or throwing")
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? CopilotAPIError else {
            return false
        }
        switch apiError {
        case .requestFailed(let statusCode, _):
            return (500...599).contains(statusCode)
        case .networkError:
            return true
        case .invalidURL, .decodingFailed, .streamingFailed, .unauthorized:
            return false
        }
    }
}