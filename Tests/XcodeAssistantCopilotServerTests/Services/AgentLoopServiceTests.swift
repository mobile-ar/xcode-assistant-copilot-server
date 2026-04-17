@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

private func makeToolCall(
    name: String,
    id: String? = nil,
    arguments: String = "{}"
) -> ToolCall {
    ToolCall(
        index: 0,
        id: id ?? "call_\(name)",
        type: "function",
        function: ToolCallFunction(name: name, arguments: arguments)
    )
}

private func makeCredentials() -> CopilotCredentials {
    CopilotCredentials(token: "mock-token", apiEndpoint: "https://api.github.com")
}

private func makeRequest(model: String = "gpt-4") -> ChatCompletionRequest {
    ChatCompletionRequest(
        model: model,
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello"))]
    )
}

private func makeService(
    copilotAPI: CopilotAPIServiceProtocol = MockCopilotAPIService(),
    mcpToolExecutor: MCPToolExecutorProtocol = MockMCPToolExecutor(),
    modelEndpointResolver: ModelEndpointResolverProtocol = MockModelEndpointResolver(),
    reasoningEffortResolver: ReasoningEffortResolverProtocol = MockReasoningEffortResolver(),
    configurationStore: ConfigurationStore = ConfigurationStore(initial: ServerConfiguration()),
    logger: LoggerProtocol = MockLogger()
) -> AgentLoopService {
    AgentLoopService(
        copilotAPI: copilotAPI,
        mcpToolExecutor: mcpToolExecutor,
        modelEndpointResolver: modelEndpointResolver,
        reasoningEffortResolver: reasoningEffortResolver,
        responsesTranslator: ResponsesAPITranslator(logger: logger),
        configurationStore: configurationStore,
        logger: logger
    )
}

@Suite("AgentLoopService")
struct AgentLoopServiceTests {

    @Test func writesRoleDeltaFirst() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Done."))
        ]

        let config = ServerConfiguration()
        let service = makeService(copilotAPI: copilotAPI, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(writer.roleDeltaWritten)
    }

    @Test func callsFinishWhenLoopCompletes() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "Final answer."))
        ]

        let service = makeService(copilotAPI: copilotAPI)
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(writer.finishCalled)
    }

    @Test func passesFinalContentToWriter() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeContentStream(content: "The answer is 42."))
        ]

        let service = makeService(copilotAPI: copilotAPI)
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(writer.finalContent == "The answer is 42.")
        #expect(writer.finalHadToolUse == false)
    }

    @Test func writesToolCallProgressBeforeExecuting() async {
        let mcpToolExecutor = MockMCPToolExecutor()
        mcpToolExecutor.setResult("struct Foo {}", for: "read_file")

        let copilotAPI = MockCopilotAPIService()
        let toolCall = makeToolCall(name: "read_file", id: "call_rf", arguments: #"{"filePath":"Sources/Foo.swift"}"#)
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Done."))
        ]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, mcpToolExecutor: mcpToolExecutor, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: ["read_file": "s"],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("`read_file`"))
    }

    @Test func setsHadToolUseTrueWhenMCPToolExecuted() async {
        let mcpToolExecutor = MockMCPToolExecutor()
        mcpToolExecutor.setResult("results", for: "search")

        let copilotAPI = MockCopilotAPIService()
        let toolCall = makeToolCall(name: "search", id: "call_s")
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Here are results."))
        ]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["search"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, mcpToolExecutor: mcpToolExecutor, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: ["search": "s"],
            writer: writer
        )

        #expect(writer.finalHadToolUse == true)
    }

    @Test func writesWarningProgressForBlockedCLITool() async {
        let copilotAPI = MockCopilotAPIService()
        let cliToolCall = makeToolCall(name: "rm", id: "call_rm")
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Cannot run rm."))
        ]

        let config = ServerConfiguration(
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("`rm`"))
        #expect(combined.contains("✗"))
    }

    @Test func writesToolCallProgressForBlockedCLITool() async {
        let copilotAPI = MockCopilotAPIService()
        let cliToolCall = makeToolCall(name: "bash", id: "call_bash", arguments: #"{"command":"rm -rf /"}"#)
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Blocked."))
        ]

        let config = ServerConfiguration(
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("`bash`"))
    }

    @Test func writesEmptyToolResultForSuccessfulMCPCall() async {
        let mcpToolExecutor = MockMCPToolExecutor()
        mcpToolExecutor.setResult("import SwiftUI", for: "read_file")

        let copilotAPI = MockCopilotAPIService()
        let toolCall = makeToolCall(name: "read_file", id: "call_rf")
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Done."))
        ]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["read_file"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, mcpToolExecutor: mcpToolExecutor, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: ["read_file": "s"],
            writer: writer
        )

        let nonToolCallTexts = writer.progressTexts.filter { !$0.contains("`read_file`") }
        #expect(nonToolCallTexts.allSatisfy { !$0.contains("✗") })
    }

    @Test func writesWarningProgressForFailedMCPCall() async {
        let mcpToolExecutor = MockMCPToolExecutor()
        mcpToolExecutor.setError(MCPBridgeError.toolExecutionFailed("timeout"), for: "run")

        let copilotAPI = MockCopilotAPIService()
        let toolCall = makeToolCall(name: "run", id: "call_run")
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [toolCall])),
            .success(MockCopilotAPIService.makeContentStream(content: "Failed."))
        ]

        let config = ServerConfiguration(
            mcpServers: ["s": MCPServerConfiguration(type: .local, command: "cmd", allowedTools: ["run"])],
            autoApprovePermissions: .kinds([.read, .mcp])
        )
        let service = makeService(copilotAPI: copilotAPI, mcpToolExecutor: mcpToolExecutor, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: ["run": "s"],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("✗"))
    }

    @Test func passesAllowedCLIToolCallsAsFinalToolCalls() async {
        let copilotAPI = MockCopilotAPIService()
        let cliToolCall = makeToolCall(name: "grep", id: "call_grep")
        copilotAPI.streamChatCompletionsResults = [
            .success(MockCopilotAPIService.makeToolCallStream(toolCalls: [cliToolCall]))
        ]

        let config = ServerConfiguration(
            allowedCliTools: ["grep"],
            autoApprovePermissions: .kinds([.read, .shell])
        )
        let service = makeService(copilotAPI: copilotAPI, configurationStore: ConfigurationStore(initial: config))
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(writer.finalToolCalls?.count == 1)
        #expect(writer.finalToolCalls?.first?.function.name == "grep")
        #expect(writer.finishCalled)
    }

    @Test func writesStreamingErrorProgressOnCollectFailure() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.streamingFailed("connection reset"))
        ]

        let service = makeService(copilotAPI: copilotAPI)
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("✗"))
        #expect(writer.finishCalled)
    }

    @Test func reasoningEffortRetryOnGeneric400DowngradesEffort() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
            .success(MockCopilotAPIService.makeContentStream(content: "Success after retry"))
        ]

        let reasoningResolver = MockReasoningEffortResolver()
        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: .xhigh)
        let service = makeService(
            copilotAPI: copilotAPI,
            reasoningEffortResolver: reasoningResolver,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(copilotAPI.streamChatCompletionsCallCount == 2)
        #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .high)
        #expect(reasoningResolver.recordedMaxEfforts.contains { $0.effort == .high })
        #expect(logger.errorMessages.contains { $0.contains("HTTP 400") && $0.contains("xhigh") })
        #expect(logger.infoMessages.contains { $0.contains("Downgrading reasoning effort") })
    }

    @Test func reasoningEffortRetryDowngradesThroughMultipleLevels() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
            .success(MockCopilotAPIService.makeContentStream(content: "Success after two downgrades"))
        ]

        let reasoningResolver = MockReasoningEffortResolver()
        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: .xhigh)
        let service = makeService(
            copilotAPI: copilotAPI,
            reasoningEffortResolver: reasoningResolver,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(copilotAPI.streamChatCompletionsCallCount == 3)
        #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .high)
        #expect(copilotAPI.capturedChatRequests[2].reasoningEffort == .medium)
    }

    @Test func reasoningEffortRetryRemovesEffortWhenAtLowestLevel() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request")),
            .success(MockCopilotAPIService.makeContentStream(content: "Success without reasoning"))
        ]

        let reasoningResolver = MockReasoningEffortResolver()
        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: .low)
        let service = makeService(
            copilotAPI: copilotAPI,
            reasoningEffortResolver: reasoningResolver,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(copilotAPI.streamChatCompletionsCallCount == 2)
        #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == nil)
        #expect(logger.infoMessages.contains { $0.contains("no lower level available") })
    }

    @Test func reasoningEffortRetryDoesNotRetryNon400Errors() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 500, body: "Internal Server Error"))
        ]

        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: .xhigh)
        let service = makeService(
            copilotAPI: copilotAPI,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("✗"))
        #expect(copilotAPI.streamChatCompletionsCallCount == 1)
    }

    @Test func reasoningEffortRetryDoesNotRetryWhenEffortIsNil() async {
        let copilotAPI = MockCopilotAPIService()
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: "Bad Request"))
        ]

        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: nil)
        let service = makeService(
            copilotAPI: copilotAPI,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        let combined = writer.allProgressText
        #expect(combined.contains("✗"))
        #expect(copilotAPI.streamChatCompletionsCallCount == 1)
    }

    @Test func reasoningEffortRetryLogsErrorBodyOn400() async {
        let copilotAPI = MockCopilotAPIService()
        let detailedErrorBody = "{\"error\":{\"message\":\"reasoning_effort is not supported\",\"type\":\"invalid_request_error\"}}"
        copilotAPI.streamChatCompletionsResults = [
            .failure(CopilotAPIError.requestFailed(statusCode: 400, body: detailedErrorBody)),
            .success(MockCopilotAPIService.makeContentStream(content: "OK"))
        ]

        let logger = MockLogger()
        let config = ServerConfiguration(reasoningEffort: .high)
        let service = makeService(
            copilotAPI: copilotAPI,
            configurationStore: ConfigurationStore(initial: config),
            logger: logger
        )
        let writer = MockAgentStreamWriter()

        await service.runAgentLoop(
            request: makeRequest(),
            credentials: makeCredentials(),
            allTools: [],
            mcpToolServerMap: [:],
            writer: writer
        )

        #expect(copilotAPI.streamChatCompletionsCallCount == 2)
        #expect(logger.errorMessages.contains { $0.contains(detailedErrorBody) })
        #expect(copilotAPI.capturedChatRequests[1].reasoningEffort == .medium)
    }
}