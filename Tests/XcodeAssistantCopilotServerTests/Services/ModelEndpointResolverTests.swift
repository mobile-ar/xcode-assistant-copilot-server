import Testing
import Foundation
@testable import XcodeAssistantCopilotServer

struct MockCopilotAPIService: CopilotAPIServiceProtocol {
    let models: [CopilotModel]
    let shouldThrow: Error?

    init(models: [CopilotModel] = [], shouldThrow: Error? = nil) {
        self.models = models
        self.shouldThrow = shouldThrow
    }

    func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
        if let error = shouldThrow {
            throw error
        }
        return models
    }

    func streamChatCompletions(
        request: CopilotChatRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        fatalError("Not used in these tests")
    }

    func streamResponses(
        request: ResponsesAPIRequest,
        credentials: CopilotCredentials
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        fatalError("Not used in these tests")
    }
}

private let testCredentials = CopilotCredentials(
    token: "test-token",
    apiEndpoint: "https://api.test.githubcopilot.com"
)

@Test func copilotModelRequiresResponsesAPIWhenOnlyResponses() {
    let model = CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"])
    #expect(model.requiresResponsesAPI == true)
}

@Test func copilotModelDoesNotRequireResponsesAPIWhenBothSupported() {
    let model = CopilotModel(id: "gpt-5.1", supportedEndpoints: ["/chat/completions", "/responses"])
    #expect(model.requiresResponsesAPI == false)
}

@Test func copilotModelDoesNotRequireResponsesAPIWhenOnlyChatCompletions() {
    let model = CopilotModel(id: "claude-sonnet-4", supportedEndpoints: ["/chat/completions"])
    #expect(model.requiresResponsesAPI == false)
}

@Test func copilotModelDoesNotRequireResponsesAPIWhenNoEndpoints() {
    let model = CopilotModel(id: "gpt-4")
    #expect(model.requiresResponsesAPI == false)
}

@Test func copilotModelSupportsResponsesAPI() {
    let both = CopilotModel(id: "gpt-5.1", supportedEndpoints: ["/chat/completions", "/responses"])
    #expect(both.supportsResponsesAPI == true)

    let onlyResponses = CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"])
    #expect(onlyResponses.supportsResponsesAPI == true)

    let onlyChat = CopilotModel(id: "claude-sonnet-4", supportedEndpoints: ["/chat/completions"])
    #expect(onlyChat.supportsResponsesAPI == false)

    let noEndpoints = CopilotModel(id: "gpt-4")
    #expect(noEndpoints.supportsResponsesAPI == false)
}

@Test func copilotModelSupportsChatCompletions() {
    let both = CopilotModel(id: "gpt-5.1", supportedEndpoints: ["/chat/completions", "/responses"])
    #expect(both.supportsChatCompletions == true)

    let onlyChat = CopilotModel(id: "claude-sonnet-4", supportedEndpoints: ["/chat/completions"])
    #expect(onlyChat.supportsChatCompletions == true)

    let onlyResponses = CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"])
    #expect(onlyResponses.supportsChatCompletions == false)

    let noEndpoints = CopilotModel(id: "gpt-4")
    #expect(noEndpoints.supportsChatCompletions == true)
}

@Test func copilotModelSupportedEndpointsDecodes() throws {
    let json = """
    {"id":"gpt-5.1-codex","name":"GPT-5.1-Codex","version":"gpt-5.1-codex","supported_endpoints":["/responses"]}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-5.1-codex")
    #expect(model.supportedEndpoints == ["/responses"])
    #expect(model.requiresResponsesAPI == true)
}

@Test func copilotModelSupportedEndpointsDecodesMultiple() throws {
    let json = """
    {"id":"gpt-5.1","name":"GPT-5.1","version":"gpt-5.1","supported_endpoints":["/chat/completions","/responses"]}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.supportedEndpoints == ["/chat/completions", "/responses"])
    #expect(model.requiresResponsesAPI == false)
}

@Test func copilotModelSupportedEndpointsDecodesWhenMissing() throws {
    let json = """
    {"id":"gpt-4","name":"GPT 4","version":"gpt-4-0613"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.supportedEndpoints == nil)
    #expect(model.requiresResponsesAPI == false)
    #expect(model.supportsChatCompletions == true)
}

@Test func resolverReturnsChatCompletionsForUnknownModel() async {
    let mockAPI = MockCopilotAPIService(models: [])
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "unknown-model", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
}

@Test func resolverReturnsChatCompletionsForLegacyModel() async {
    let models = [
        CopilotModel(id: "gpt-4", name: "GPT 4")
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-4", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
}

@Test func resolverReturnsResponsesForCodexModel() async {
    let models = [
        CopilotModel(id: "gpt-5.1-codex", name: "GPT-5.1-Codex", supportedEndpoints: ["/responses"]),
        CopilotModel(id: "gpt-4o", name: "GPT-4o", supportedEndpoints: ["/chat/completions"])
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials)
    #expect(endpoint == .responses)
}

@Test func resolverReturnsChatCompletionsForDualEndpointModel() async {
    let models = [
        CopilotModel(id: "gpt-5.1", name: "GPT-5.1", supportedEndpoints: ["/chat/completions", "/responses"])
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-5.1", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
}

@Test func resolverReturnsChatCompletionsForChatOnlyModel() async {
    let models = [
        CopilotModel(id: "claude-sonnet-4", name: "Claude Sonnet 4", supportedEndpoints: ["/chat/completions"])
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "claude-sonnet-4", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
}

@Test func resolverCachesModelList() async {
    var callCount = 0
    let models = [
        CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"])
    ]

    final class CountingAPIService: CopilotAPIServiceProtocol, @unchecked Sendable {
        let models: [CopilotModel]
        var callCount = 0

        init(models: [CopilotModel]) {
            self.models = models
        }

        func listModels(credentials: CopilotCredentials) async throws -> [CopilotModel] {
            callCount += 1
            return models
        }

        func streamChatCompletions(
            request: CopilotChatRequest,
            credentials: CopilotCredentials
        ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
            fatalError("Not used")
        }

        func streamResponses(
            request: ResponsesAPIRequest,
            credentials: CopilotCredentials
        ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
            fatalError("Not used")
        }
    }

    let countingAPI = CountingAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: countingAPI, logger: logger)

    let first = await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials)
    #expect(first == .responses)

    let second = await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials)
    #expect(second == .responses)

    #expect(countingAPI.callCount == 1)
}

@Test func resolverDefaultsToChatCompletionsOnFetchError() async {
    struct FetchError: Error {}

    let mockAPI = MockCopilotAPIService(shouldThrow: FetchError())
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
    #expect(logger.warnMessages.count == 1)
    #expect(logger.warnMessages[0].contains("Failed to refresh"))
}

@Test func resolverHandlesMultipleModelsCorrectly() async {
    let models = [
        CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"]),
        CopilotModel(id: "gpt-5.1-codex-max", supportedEndpoints: ["/responses"]),
        CopilotModel(id: "gpt-5.1", supportedEndpoints: ["/chat/completions", "/responses"]),
        CopilotModel(id: "claude-sonnet-4", supportedEndpoints: ["/chat/completions"]),
        CopilotModel(id: "gpt-4"),
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    #expect(await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials) == .responses)
    #expect(await resolver.endpoint(for: "gpt-5.1-codex-max", credentials: testCredentials) == .responses)
    #expect(await resolver.endpoint(for: "gpt-5.1", credentials: testCredentials) == .chatCompletions)
    #expect(await resolver.endpoint(for: "claude-sonnet-4", credentials: testCredentials) == .chatCompletions)
    #expect(await resolver.endpoint(for: "gpt-4", credentials: testCredentials) == .chatCompletions)
    #expect(await resolver.endpoint(for: "nonexistent-model", credentials: testCredentials) == .chatCompletions)
}

@Test func resolverLogsDebugOnRefresh() async {
    let models = [
        CopilotModel(id: "gpt-5.1-codex", supportedEndpoints: ["/responses"])
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    _ = await resolver.endpoint(for: "gpt-5.1-codex", credentials: testCredentials)

    #expect(logger.debugMessages.count == 1)
    #expect(logger.debugMessages[0].contains("Refreshed model endpoint cache"))
}

@Test func modelEndpointEquality() {
    let chat1: ModelEndpoint = .chatCompletions
    let chat2: ModelEndpoint = .chatCompletions
    let responses1: ModelEndpoint = .responses
    let responses2: ModelEndpoint = .responses

    #expect(chat1 == chat2)
    #expect(responses1 == responses2)
    #expect(chat1 != responses1)
}

@Test func copilotModelSupportedEndpointsRealWorldCodexModel() throws {
    let json = """
    {
        "capabilities": {
            "family": "gpt-5.1-codex",
            "limits": {"max_context_window_tokens": 400000, "max_output_tokens": 128000, "max_prompt_tokens": 128000},
            "object": "model_capabilities",
            "supports": {"parallel_tool_calls": true, "streaming": true, "structured_outputs": true, "tool_calls": true, "vision": true},
            "tokenizer": "o200k_base",
            "type": "chat"
        },
        "id": "gpt-5.1-codex",
        "model_picker_category": "powerful",
        "model_picker_enabled": true,
        "name": "GPT-5.1-Codex",
        "object": "model",
        "preview": false,
        "supported_endpoints": ["/responses"],
        "vendor": "OpenAI",
        "version": "gpt-5.1-codex"
    }
    """

    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-5.1-codex")
    #expect(model.name == "GPT-5.1-Codex")
    #expect(model.version == "gpt-5.1-codex")
    #expect(model.supportedEndpoints == ["/responses"])
    #expect(model.requiresResponsesAPI == true)
    #expect(model.supportsResponsesAPI == true)
    #expect(model.supportsChatCompletions == false)
    #expect(model.capabilities?.family == "gpt-5.1-codex")
    #expect(model.capabilities?.type == "chat")
    #expect(model.capabilities?.supports?.streaming == true)
    #expect(model.capabilities?.supports?.toolCalls == true)
    #expect(model.capabilities?.supports?.parallelToolCalls == true)
    #expect(model.capabilities?.supports?.structuredOutputs == true)
    #expect(model.capabilities?.supports?.vision == true)
}

@Test func copilotModelSupportedEndpointsRealWorldDualModel() throws {
    let json = """
    {
        "capabilities": {
            "family": "gpt-5.1",
            "object": "model_capabilities",
            "supports": {"parallel_tool_calls": true, "streaming": true, "structured_outputs": true, "tool_calls": true, "vision": true},
            "tokenizer": "o200k_base",
            "type": "chat"
        },
        "id": "gpt-5.1",
        "name": "GPT-5.1",
        "object": "model",
        "preview": false,
        "supported_endpoints": ["/chat/completions", "/responses"],
        "vendor": "OpenAI",
        "version": "gpt-5.1"
    }
    """

    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-5.1")
    #expect(model.supportedEndpoints == ["/chat/completions", "/responses"])
    #expect(model.requiresResponsesAPI == false)
    #expect(model.supportsResponsesAPI == true)
    #expect(model.supportsChatCompletions == true)
}

@Test func copilotModelSupportedEndpointsRealWorldChatOnlyModel() throws {
    let json = """
    {
        "capabilities": {
            "family": "claude-sonnet-4",
            "object": "model_capabilities",
            "supports": {"streaming": true, "tool_calls": true, "vision": true},
            "tokenizer": "o200k_base",
            "type": "chat"
        },
        "id": "claude-sonnet-4",
        "name": "Claude Sonnet 4",
        "object": "model",
        "preview": false,
        "supported_endpoints": ["/chat/completions"],
        "vendor": "Anthropic",
        "version": "claude-sonnet-4"
    }
    """

    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "claude-sonnet-4")
    #expect(model.supportedEndpoints == ["/chat/completions"])
    #expect(model.requiresResponsesAPI == false)
    #expect(model.supportsResponsesAPI == false)
    #expect(model.supportsChatCompletions == true)
}

@Test func copilotModelSupportedEndpointsRealWorldLegacyModel() throws {
    let json = """
    {
        "capabilities": {
            "family": "gpt-4",
            "object": "model_capabilities",
            "supports": {"streaming": true, "tool_calls": true},
            "tokenizer": "cl100k_base",
            "type": "chat"
        },
        "id": "gpt-4",
        "name": "GPT 4",
        "object": "model",
        "preview": false,
        "vendor": "Azure OpenAI",
        "version": "gpt-4-0613"
    }
    """

    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-4")
    #expect(model.supportedEndpoints == nil)
    #expect(model.requiresResponsesAPI == false)
    #expect(model.supportsChatCompletions == true)
}

@Test func resolverReturnsChatCompletionsForModelWithNoSupportedEndpointsField() async {
    let models = [
        CopilotModel(id: "gpt-3.5-turbo", name: "GPT 3.5")
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-3.5-turbo", credentials: testCredentials)
    #expect(endpoint == .chatCompletions)
}

@Test func resolverReturnsResponsesForCodexMaxModel() async {
    let models = [
        CopilotModel(id: "gpt-5.1-codex-max", supportedEndpoints: ["/responses"])
    ]
    let mockAPI = MockCopilotAPIService(models: models)
    let logger = MockLogger()
    let resolver = ModelEndpointResolver(copilotAPI: mockAPI, logger: logger)

    let endpoint = await resolver.endpoint(for: "gpt-5.1-codex-max", credentials: testCredentials)
    #expect(endpoint == .responses)
}
