import Foundation
import Testing
import Synchronization
@testable import XcodeAssistantCopilotServer

@Test func successOnFirstAttemptDoesNotRetry() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    let result = try await policy.execute(logger: MockLogger()) {
        callCount.withLock { $0 += 1 }
        return "hello"
    }

    #expect(result == "hello")
    #expect(callCount.withLock { $0 } == 1)
}

@Test func retriesOn5xxAndSucceeds() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    let result = try await policy.execute(logger: MockLogger()) {
        let count = callCount.withLock { c -> Int in
            c += 1
            return c
        }
        if count == 1 {
            throw CopilotAPIError.requestFailed(statusCode: 500, body: "error")
        }
        return "recovered"
    }

    #expect(result == "recovered")
    #expect(callCount.withLock { $0 } == 2)
}

@Test func retriesOnNetworkErrorAndSucceeds() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    let result = try await policy.execute(logger: MockLogger()) {
        let count = callCount.withLock { c -> Int in
            c += 1
            return c
        }
        if count == 1 {
            throw CopilotAPIError.networkError("timeout")
        }
        return "ok"
    }

    #expect(result == "ok")
    #expect(callCount.withLock { $0 } == 2)
}

@Test func exhaustsRetriesAndThrows() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    await #expect(throws: CopilotAPIError.self) {
        try await policy.execute(logger: MockLogger()) {
            callCount.withLock { $0 += 1 }
            throw CopilotAPIError.requestFailed(statusCode: 502, body: "bad gateway")
        }
    }

    #expect(callCount.withLock { $0 } == 3)
}

@Test func doesNotRetryOn401Unauthorized() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    await #expect(throws: CopilotAPIError.self) {
        try await policy.execute(logger: MockLogger()) {
            callCount.withLock { $0 += 1 }
            throw CopilotAPIError.unauthorized
        }
    }

    #expect(callCount.withLock { $0 } == 1)
}

@Test func doesNotRetryOn400ClientError() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    await #expect(throws: CopilotAPIError.self) {
        try await policy.execute(logger: MockLogger()) {
            callCount.withLock { $0 += 1 }
            throw CopilotAPIError.requestFailed(statusCode: 400, body: "bad request")
        }
    }

    #expect(callCount.withLock { $0 } == 1)
}

@Test func doesNotRetryOnDecodingFailed() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    await #expect(throws: CopilotAPIError.self) {
        try await policy.execute(logger: MockLogger()) {
            callCount.withLock { $0 += 1 }
            throw CopilotAPIError.decodingFailed("parse error")
        }
    }

    #expect(callCount.withLock { $0 } == 1)
}

@Test func disabledPolicyDoesNotRetry() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy.disabled

    await #expect(throws: CopilotAPIError.self) {
        try await policy.execute(logger: MockLogger()) {
            callCount.withLock { $0 += 1 }
            throw CopilotAPIError.requestFailed(statusCode: 500, body: "error")
        }
    }

    #expect(callCount.withLock { $0 } == 1)
}

@Test func retriesOn503ServiceUnavailable() async throws {
    let callCount = Mutex(0)
    let policy = RetryPolicy(maxRetries: 2, baseDelayMilliseconds: 1)

    let result = try await policy.execute(logger: MockLogger()) {
        let count = callCount.withLock { c -> Int in
            c += 1
            return c
        }
        if count == 1 {
            throw CopilotAPIError.requestFailed(statusCode: 503, body: "unavailable")
        }
        return "available"
    }

    #expect(result == "available")
    #expect(callCount.withLock { $0 } == 2)
}