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
    func streamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error>
}

public struct CopilotChatRequest: Sendable {
    public let model: String
    public let messages: [ChatCompletionMessage]
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?
    public let stop: StopSequence?
    public let tools: [Tool]?
    public let toolChoice: AnyCodable?
    public let reasoningEffort: ReasoningEffort?
    public let stream: Bool

    public init(
        model: String,
        messages: [ChatCompletionMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stop: StopSequence? = nil,
        tools: [Tool]? = nil,
        toolChoice: AnyCodable? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        stream: Bool = true
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stop = stop
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoningEffort = reasoningEffort
        self.stream = stream
    }
}

public final class CopilotAPIService: CopilotAPIServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let logger: LoggerProtocol
    private let sseParser: SSEParser

    private static let modelsPath = "/models"
    private static let chatCompletionsPath = "/chat/completions"

    public init(logger: LoggerProtocol, session: URLSession = .shared) {
        self.logger = logger
        self.session = session
        self.sseParser = SSEParser()
    }

    public func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        let url = try buildURL(baseURL: credentials.apiEndpoint, path: Self.modelsPath)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, token: credentials.token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CopilotAPIError.networkError(error.localizedDescription)
        }

        try validateHTTPResponse(response, data: data)

        do {
            let modelsResponse = try JSONDecoder().decode(CopilotModelsResponse.self, from: data)
            let models = modelsResponse.allModels
            logger.debug("Fetched \(models.count) model(s) from Copilot API")
            return models
        } catch {
            throw CopilotAPIError.decodingFailed(error.localizedDescription)
        }
    }

    public func streamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let url = try buildURL(baseURL: credentials.apiEndpoint, path: Self.chatCompletionsPath)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        applyHeaders(to: &urlRequest, token: credentials.token)
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("conversation-panel", forHTTPHeaderField: "Openai-Intent")

        let body = buildRequestBody(from: request)
        urlRequest.httpBody = try encodeBody(body)

        logger.debug("Sending chat completion request for model: \(request.model) to \(credentials.apiEndpoint)")

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotAPIError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 {
            throw CopilotAPIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var collectedData = Data()
            for try await byte in bytes {
                collectedData.append(byte)
            }
            let body = String(data: collectedData, encoding: .utf8) ?? ""
            throw CopilotAPIError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        return sseParser.parse(bytes: bytes)
    }

    private func buildURL(baseURL: String, path: String) throws -> URL {
        let urlString = baseURL + path
        guard let url = URL(string: urlString) else {
            throw CopilotAPIError.invalidURL(urlString)
        }
        return url
    }

    private func applyHeaders(to request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.setValue("github-copilot", forHTTPHeaderField: "Openai-Organization")
        request.setValue("Xcode/26.0", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-xcode/0.1.0", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
    }

    private func buildRequestBody(from request: CopilotChatRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "stream": request.stream,
        ]

        body["messages"] = request.messages.map { encodeMessage($0) }

        if let temperature = request.temperature {
            body["temperature"] = temperature
        }
        if let topP = request.topP {
            body["top_p"] = topP
        }
        if let maxTokens = request.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let stop = request.stop {
            switch stop {
            case .single(let value):
                body["stop"] = value
            case .multiple(let values):
                body["stop"] = values
            }
        }
        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = encodeTools(tools)
        }
        if let toolChoice = request.toolChoice {
            body["tool_choice"] = encodeAnyCodable(toolChoice)
        }
        if let reasoningEffort = request.reasoningEffort {
            body["reasoning_effort"] = reasoningEffort.rawValue
        }

        return body
    }

    private func encodeMessage(_ message: ChatCompletionMessage) -> [String: Any] {
        var dict: [String: Any] = [:]

        if let role = message.role {
            dict["role"] = role.rawValue
        }

        if let content = message.content {
            switch content {
            case .text(let text):
                dict["content"] = text
            case .parts(let parts):
                dict["content"] = parts.map { part in
                    var partDict: [String: Any] = ["type": part.type]
                    if let text = part.text {
                        partDict["text"] = text
                    }
                    return partDict
                }
            case .none:
                dict["content"] = NSNull()
            }
        }

        if let name = message.name {
            dict["name"] = name
        }

        if let toolCalls = message.toolCalls {
            dict["tool_calls"] = toolCalls.map { tc in
                var tcDict: [String: Any] = [
                    "function": [
                        "name": tc.function.name,
                        "arguments": tc.function.arguments,
                    ]
                ]
                if let index = tc.index { tcDict["index"] = index }
                if let id = tc.id { tcDict["id"] = id }
                if let type = tc.type { tcDict["type"] = type }
                return tcDict
            }
        }

        if let toolCallId = message.toolCallId {
            dict["tool_call_id"] = toolCallId
        }

        return dict
    }

    private func encodeTools(_ tools: [Tool]) -> [[String: Any]] {
        tools.map { tool in
            var funcDict: [String: Any] = ["name": tool.function.name]
            if let description = tool.function.description {
                funcDict["description"] = description
            }
            if let parameters = tool.function.parameters {
                funcDict["parameters"] = parameters.mapValues { encodeAnyCodable($0) }
            }
            return [
                "type": tool.type,
                "function": funcDict,
            ]
        }
    }

    private func encodeAnyCodable(_ value: AnyCodable) -> Any {
        switch value.value {
        case .string(let s): s
        case .int(let i): i
        case .double(let d): d
        case .bool(let b): b
        case .null: NSNull()
        case .array(let arr): arr.map { encodeAnyCodable($0) }
        case .dictionary(let dict): dict.mapValues { encodeAnyCodable($0) }
        }
    }

    private func encodeBody(_ body: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw CopilotAPIError.streamingFailed("Failed to encode request body: \(error.localizedDescription)")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotAPIError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 {
            throw CopilotAPIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CopilotAPIError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }
}