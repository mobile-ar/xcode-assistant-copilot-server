import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private func makeService(httpClient: MockHTTPClient = MockHTTPClient(), logger: LoggerProtocol = MockLogger()) -> CopilotAPIService {
    CopilotAPIService(httpClient: httpClient, logger: logger)
}

private let testCredentials = CopilotCredentials(token: "test-copilot-token", apiEndpoint: "https://api.individual.githubcopilot.com")

@Test func listModelsReturnsDecodedModels() async throws {
    let mock = MockHTTPClient()
    let modelsJSON = """
    {"data":[{"id":"gpt-4o"},{"id":"o3-mini"}]}
    """
    mock.executeResults = [.success(DataResponse(data: modelsJSON.data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock)
    let models = try await service.listModels(credentials: testCredentials)

    #expect(models.count == 2)
    #expect(models[0].id == "gpt-4o")
    #expect(models[1].id == "o3-mini")
    #expect(mock.executeCallCount == 1)
}

@Test func listModelsReturnsEmptyArrayWhenNoModels() async throws {
    let mock = MockHTTPClient()
    let modelsJSON = """
    {"data":[]}
    """
    mock.executeResults = [.success(DataResponse(data: modelsJSON.data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock)
    let models = try await service.listModels(credentials: testCredentials)

    #expect(models.isEmpty)
}

@Test func listModelsThrowsUnauthorizedOn401() async {
    let mock = MockHTTPClient()
    mock.executeResults = [.success(DataResponse(data: Data(), statusCode: 401))]

    let service = makeService(httpClient: mock)

    do {
        _ = try await service.listModels(credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.unauthorized")
    } catch let error as CopilotAPIError {
        guard case .unauthorized = error else {
            Issue.record("Expected .unauthorized, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func listModelsThrowsRequestFailedOnNon2xx() async {
    let mock = MockHTTPClient()
    let errorBody = "{\"error\":\"forbidden\"}"
    mock.executeResults = [.success(DataResponse(data: errorBody.data(using: .utf8)!, statusCode: 403))]

    let service = makeService(httpClient: mock)

    do {
        _ = try await service.listModels(credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.requestFailed")
    } catch let error as CopilotAPIError {
        guard case .requestFailed(let statusCode, let body) = error else {
            Issue.record("Expected .requestFailed, got \(error)")
            return
        }
        #expect(statusCode == 403)
        #expect(body.contains("forbidden"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func listModelsThrowsDecodingFailedOnInvalidJSON() async {
    let mock = MockHTTPClient()
    mock.executeResults = [.success(DataResponse(data: "not json".data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock)

    do {
        _ = try await service.listModels(credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.decodingFailed")
    } catch let error as CopilotAPIError {
        guard case .decodingFailed = error else {
            Issue.record("Expected .decodingFailed, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func listModelsThrowsNetworkErrorOnHTTPClientError() async {
    let mock = MockHTTPClient()
    mock.executeResults = [.failure(HTTPClientError.networkError("connection refused"))]

    let service = makeService(httpClient: mock)

    do {
        _ = try await service.listModels(credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.networkError")
    } catch let error as CopilotAPIError {
        guard case .networkError(let message) = error else {
            Issue.record("Expected .networkError, got \(error)")
            return
        }
        #expect(message.contains("connection refused"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func listModelsSendsListModelsEndpoint() async throws {
    let mock = MockHTTPClient()
    let modelsJSON = """
    {"data":[{"id":"gpt-4o"}]}
    """
    mock.executeResults = [.success(DataResponse(data: modelsJSON.data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock)
    _ = try await service.listModels(credentials: testCredentials)

    #expect(mock.sentEndpoints.count == 1)
    let sent = mock.sentEndpoints[0]
    #expect(sent.method == .get)
    #expect(sent.path == "/models")
    #expect(sent.baseURL == testCredentials.apiEndpoint)
}

@Test func streamChatCompletionsReturnsSSEEventsOnSuccess() async throws {
    let mock = MockHTTPClient()
    let lines = AsyncThrowingStream<String, Error> { continuation in
        continuation.yield("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}")
        continuation.yield("")
        continuation.yield("data: [DONE]")
        continuation.yield("")
        continuation.finish()
    }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
    let stream = try await service.streamChatCompletions(request: request, credentials: testCredentials)

    var events: [SSEEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.count >= 1)
    #expect(mock.streamCallCount == 1)
}

@Test func streamChatCompletionsThrowsUnauthorizedOn401() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 401, content: .errorBody("Unauthorized")))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )

    do {
        _ = try await service.streamChatCompletions(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.unauthorized")
    } catch let error as CopilotAPIError {
        guard case .unauthorized = error else {
            Issue.record("Expected .unauthorized, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamChatCompletionsThrowsRequestFailedOnNon2xx() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 500, content: .errorBody("Internal Server Error")))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )

    do {
        _ = try await service.streamChatCompletions(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.requestFailed")
    } catch let error as CopilotAPIError {
        guard case .requestFailed(let statusCode, let body) = error else {
            Issue.record("Expected .requestFailed, got \(error)")
            return
        }
        #expect(statusCode == 500)
        #expect(body == "Internal Server Error")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamChatCompletionsThrowsNetworkErrorOnHTTPClientError() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.failure(HTTPClientError.networkError("timeout"))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )

    do {
        _ = try await service.streamChatCompletions(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.networkError")
    } catch let error as CopilotAPIError {
        guard case .networkError(let message) = error else {
            Issue.record("Expected .networkError, got \(error)")
            return
        }
        #expect(message.contains("timeout"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamChatCompletionsSendsChatCompletionsStreamEndpoint() async throws {
    let mock = MockHTTPClient()
    let lines = AsyncThrowingStream<String, Error> { $0.finish() }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
    _ = try await service.streamChatCompletions(request: request, credentials: testCredentials)

    #expect(mock.sentEndpoints.count == 1)
    let sent = mock.sentEndpoints[0]
    #expect(sent.method == .post)
    #expect(sent.path == "/chat/completions")
    #expect(sent.baseURL == testCredentials.apiEndpoint)
}

@Test func streamResponsesReturnsSSEEventsOnSuccess() async throws {
    let mock = MockHTTPClient()
    let lines = AsyncThrowingStream<String, Error> { continuation in
        continuation.yield("event: response.output_text.delta")
        continuation.yield("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}")
        continuation.yield("")
        continuation.yield("data: [DONE]")
        continuation.yield("")
        continuation.finish()
    }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )
    let stream = try await service.streamResponses(request: request, credentials: testCredentials)

    var events: [SSEEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.count >= 1)
    #expect(mock.streamCallCount == 1)
}

@Test func streamResponsesThrowsUnauthorizedOn401() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 401, content: .errorBody("Unauthorized")))]

    let service = makeService(httpClient: mock)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )

    do {
        _ = try await service.streamResponses(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.unauthorized")
    } catch let error as CopilotAPIError {
        guard case .unauthorized = error else {
            Issue.record("Expected .unauthorized, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamResponsesThrowsRequestFailedOnNon2xx() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 503, content: .errorBody("Service Unavailable")))]

    let service = makeService(httpClient: mock)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )

    do {
        _ = try await service.streamResponses(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.requestFailed")
    } catch let error as CopilotAPIError {
        guard case .requestFailed(let statusCode, let body) = error else {
            Issue.record("Expected .requestFailed, got \(error)")
            return
        }
        #expect(statusCode == 503)
        #expect(body == "Service Unavailable")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamResponsesThrowsNetworkErrorOnHTTPClientError() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.failure(HTTPClientError.networkError("DNS resolution failed"))]

    let service = makeService(httpClient: mock)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )

    do {
        _ = try await service.streamResponses(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.networkError")
    } catch let error as CopilotAPIError {
        guard case .networkError(let message) = error else {
            Issue.record("Expected .networkError, got \(error)")
            return
        }
        #expect(message.contains("DNS resolution failed"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func streamResponsesSendsResponsesStreamEndpoint() async throws {
    let mock = MockHTTPClient()
    let lines = AsyncThrowingStream<String, Error> { $0.finish() }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )
    _ = try await service.streamResponses(request: request, credentials: testCredentials)

    #expect(mock.sentEndpoints.count == 1)
    let sent = mock.sentEndpoints[0]
    #expect(sent.method == .post)
    #expect(sent.path == "/responses")
    #expect(sent.baseURL == testCredentials.apiEndpoint)
}

@Test func listModelsWithModelsKeyFallback() async throws {
    let mock = MockHTTPClient()
    let modelsJSON = """
    {"models":[{"id":"claude-3-opus"}]}
    """
    mock.executeResults = [.success(DataResponse(data: modelsJSON.data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock)
    let models = try await service.listModels(credentials: testCredentials)

    #expect(models.count == 1)
    #expect(models[0].id == "claude-3-opus")
}

@Test func copilotAPIErrorDescriptions() {
    let invalidURL = CopilotAPIError.invalidURL("bad://url")
    #expect(invalidURL.description.contains("bad://url"))

    let requestFailed = CopilotAPIError.requestFailed(statusCode: 500, body: "error body")
    #expect(requestFailed.description.contains("500"))
    #expect(requestFailed.description.contains("error body"))

    let networkError = CopilotAPIError.networkError("timeout")
    #expect(networkError.description.contains("timeout"))

    let decodingFailed = CopilotAPIError.decodingFailed("bad format")
    #expect(decodingFailed.description.contains("bad format"))

    let streamingFailed = CopilotAPIError.streamingFailed("connection dropped")
    #expect(streamingFailed.description.contains("connection dropped"))

    let unauthorized = CopilotAPIError.unauthorized
    #expect(unauthorized.description.contains("401"))
}

@Test func streamChatCompletionsThrowsRequestFailedOn400() async {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 400, content: .errorBody("{\"error\":\"invalid model\"}")))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "nonexistent-model",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )

    do {
        _ = try await service.streamChatCompletions(request: request, credentials: testCredentials)
        Issue.record("Expected CopilotAPIError.requestFailed")
    } catch let error as CopilotAPIError {
        guard case .requestFailed(let statusCode, let body) = error else {
            Issue.record("Expected .requestFailed, got \(error)")
            return
        }
        #expect(statusCode == 400)
        #expect(body.contains("invalid model"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func listModelsLogsModelCount() async throws {
    let mock = MockHTTPClient()
    let logger = MockLogger()
    let modelsJSON = """
    {"data":[{"id":"gpt-4o"},{"id":"o3-mini"},{"id":"claude-3-opus"}]}
    """
    mock.executeResults = [.success(DataResponse(data: modelsJSON.data(using: .utf8)!, statusCode: 200))]

    let service = makeService(httpClient: mock, logger: logger)
    _ = try await service.listModels(credentials: testCredentials)

    #expect(logger.debugMessages.contains { $0.contains("3") && $0.contains("model") })
}

@Test func streamResponsesLogsStatusCode() async throws {
    let mock = MockHTTPClient()
    let logger = MockLogger()
    let lines = AsyncThrowingStream<String, Error> { $0.finish() }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock, logger: logger)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )
    _ = try await service.streamResponses(request: request, credentials: testCredentials)

    #expect(logger.infoMessages.contains { $0.contains("200") })
}

@Test func streamChatCompletionsCollectsMultipleSSEEvents() async throws {
    let mock = MockHTTPClient()
    let lines = AsyncThrowingStream<String, Error> { continuation in
        continuation.yield("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
        continuation.yield("")
        continuation.yield("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o\",\"choices\":[{\"delta\":{\"content\":\" world\"}}]}")
        continuation.yield("")
        continuation.yield("data: [DONE]")
        continuation.yield("")
        continuation.finish()
    }
    mock.streamResults = [.success(StreamResponse(statusCode: 200, content: .lines(lines)))]

    let service = makeService(httpClient: mock)
    let request = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Say hello world"))]
    )
    let stream = try await service.streamChatCompletions(request: request, credentials: testCredentials)

    var events: [SSEEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.count == 3)
    #expect(events[0].data.contains("Hello"))
    #expect(events[1].data.contains("world"))
    #expect(events[2].isDone)
}

@Test func streamResponsesLogsErrorBody() async {
    let mock = MockHTTPClient()
    let logger = MockLogger()
    mock.streamResults = [.success(StreamResponse(statusCode: 429, content: .errorBody("Rate limit exceeded")))]

    let service = makeService(httpClient: mock, logger: logger)
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
    )

    do {
        _ = try await service.streamResponses(request: request, credentials: testCredentials)
        Issue.record("Expected an error")
    } catch {
        #expect(logger.errorMessages.contains { $0.contains("Rate limit exceeded") })
    }
}