import Foundation

public enum CopilotAPIError: Error, CustomStringConvertible {
    case invalidURL(String)
    case requestFailed(statusCode: Int, body: String)
    case networkError(String)
    case decodingFailed(String)
    case streamingFailed(String)
    case unauthorized

    public var description: String {
        switch self {
        case .invalidURL(let url):
            "Invalid Copilot API URL: \(url)"
        case .requestFailed(let statusCode, let body):
            "Copilot API request failed with HTTP \(statusCode): \(body)"
        case .networkError(let message):
            "Copilot API network error: \(message)"
        case .decodingFailed(let message):
            "Failed to decode Copilot API response: \(message)"
        case .streamingFailed(let message):
            "Copilot API streaming failed: \(message)"
        case .unauthorized:
            "Copilot API returned 401 Unauthorized. Token may be expired."
        }
    }
}

public protocol CopilotAPIServiceProtocol: Sendable {
    func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel]
    func streamChatCompletions(request: CopilotChatRequest, credentials: CopilotCredentials) async throws -> AsyncThrowingStream<SSEEvent, Error>
    func streamResponses(request: ResponsesAPIRequest, credentials: CopilotCredentials) async throws -> AsyncThrowingStream<SSEEvent, Error>
}

public struct CopilotAPIService: CopilotAPIServiceProtocol {
    private let httpClient: HTTPClientProtocol
    private let logger: LoggerProtocol
    private let sseParser: SSEParser
    private let configurationStore: ConfigurationStore
    private let requestHeaders: CopilotRequestHeadersProtocol
    private let retryPolicy: RetryPolicy

    public init(httpClient: HTTPClientProtocol, logger: LoggerProtocol, configurationStore: ConfigurationStore, requestHeaders: CopilotRequestHeadersProtocol, retryPolicy: RetryPolicy = .default) {
        self.httpClient = httpClient
        self.logger = logger
        self.sseParser = SSEParser()
        self.configurationStore = configurationStore
        self.requestHeaders = requestHeaders
        self.retryPolicy = retryPolicy
    }

    public func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        try await retryPolicy.execute(logger: logger) {
            try await self.executeListModels(credentials: credentials)
        }
    }

    private func executeListModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        let endpoint = ListModelsEndpoint(credentials: credentials, requestHeaders: requestHeaders)

        let response: DataResponse
        do {
            response = try await httpClient.execute(endpoint)
        } catch let error as HTTPClientError {
            throw CopilotAPIError.networkError(error.description)
        }

        try validateDataResponse(response)

        logger.debug("Copilot models raw response (\(response.data.count) bytes):\n\(response.data.prettyPrintedJSON)")

        do {
            let modelsResponse = try JSONDecoder().decode(CopilotModelsResponse.self, from: response.data)
            let models = modelsResponse.allModels
            logger.debug("Fetched \(models.count) model(s) from Copilot API")
            return models
        } catch let decodingError as DecodingError {
            let detail = Self.decodingErrorDetail(decodingError)
            logger.error("Models decoding failed: \(detail)")
            logger.error("Raw response body: \(response.data.prettyPrintedJSON)")
            throw CopilotAPIError.decodingFailed(detail)
        } catch {
            throw CopilotAPIError.decodingFailed(error.localizedDescription)
        }
    }

    public func streamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        try await retryPolicy.execute(logger: logger) {
            try await self.executeStreamChatCompletions(request: request, credentials: credentials)
        }
    }

    private func executeStreamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let timeout = await configurationStore.current().timeouts.streamingEndpointTimeoutSeconds
        let endpoint: ChatCompletionsStreamEndpoint
        do {
            endpoint = try ChatCompletionsStreamEndpoint(request: request, credentials: credentials, requestHeaders: requestHeaders, timeoutInterval: timeout)
        } catch {
            throw CopilotAPIError.streamingFailed("Failed to encode request body: \(error.localizedDescription)")
        }

        logger.info("Sending chat completion request for model: \(request.model) to \(credentials.apiEndpoint)/chat/completions")
        if let body = endpoint.body {
            logger.debug("Chat completions request body (\(body.count) bytes):\n\(body.prettyPrintedJSON)")
        }

        let streamResponse: StreamResponse
        do {
            streamResponse = try await httpClient.stream(endpoint)
        } catch let error as HTTPClientError {
            throw CopilotAPIError.networkError(error.description)
        }

        try validateStreamResponse(streamResponse)

        guard case .lines(let lines) = streamResponse.content else {
            throw CopilotAPIError.streamingFailed("Unexpected stream content after validation")
        }

        return sseParser.parseLines(lines)
    }

    public func streamResponses(
        request: ResponsesAPIRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        try await retryPolicy.execute(logger: logger) {
            try await self.executeStreamResponses(request: request, credentials: credentials)
        }
    }

    private func executeStreamResponses(
        request: ResponsesAPIRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let timeout = await configurationStore.current().timeouts.streamingEndpointTimeoutSeconds
        let endpoint: ResponsesStreamEndpoint
        do {
            endpoint = try ResponsesStreamEndpoint(request: request, credentials: credentials, requestHeaders: requestHeaders, timeoutInterval: timeout)
        } catch {
            logger.error("Failed to encode responses request body: \(error)")
            throw CopilotAPIError.streamingFailed("Failed to encode responses request body: \(error.localizedDescription)")
        }

        logger.info("Sending responses API request for model: \(request.model) to \(credentials.apiEndpoint)/responses")
        if let body = endpoint.body {
            logger.debug("Responses API request body (\(body.count) bytes):\n\(body.prettyPrintedJSON)")
        }

        let streamResponse: StreamResponse
        do {
            streamResponse = try await httpClient.stream(endpoint)
        } catch let error as HTTPClientError {
            throw CopilotAPIError.networkError(error.description)
        }

        logger.info("Responses API HTTP status: \(streamResponse.statusCode)")

        try validateStreamResponse(streamResponse)

        guard case .lines(let lines) = streamResponse.content else {
            throw CopilotAPIError.streamingFailed("Unexpected stream content after validation")
        }

        logger.info("Responses API stream connected successfully, beginning SSE parsing")
        return sseParser.parseLines(lines)
    }

    private func validateDataResponse(_ response: DataResponse) throws {
        if response.statusCode == 401 {
            throw CopilotAPIError.unauthorized
        }

        guard (200...299).contains(response.statusCode) else {
            let body = String(data: response.data, encoding: .utf8) ?? ""
            throw CopilotAPIError.requestFailed(statusCode: response.statusCode, body: body)
        }
    }

    static func decodingErrorDetail(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch at '\(path)': expected \(type) — \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Value not found at '\(path)': expected \(type) — \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let fullPath = path.isEmpty ? key.stringValue : "\(path).\(key.stringValue)"
            return "Key not found: '\(fullPath)' — \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Data corrupted at '\(path)' — \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func validateStreamResponse(_ response: StreamResponse) throws {
        if response.statusCode == 401 {
            if case .errorBody(let body) = response.content {
                logger.error("Copilot API returned 401 Unauthorized: \(body)")
            }
            throw CopilotAPIError.unauthorized
        }

        if case .errorBody(let body) = response.content {
            logger.error("Copilot API error response (HTTP \(response.statusCode)), body length=\(body.count) chars")
            logger.error("Copilot API error body: \(body)")
            if let data = body.data(using: .utf8) {
                logger.debug("Copilot API error body (pretty-printed):\n\(data.prettyPrintedJSON)")
            }
            throw CopilotAPIError.requestFailed(statusCode: response.statusCode, body: body)
        }
    }
}
