import Foundation
import Hummingbird
import NIOCore

struct AgentStreamingChatCompletion: ChatCompletionProtocol, Sendable {
    private let bridgeHolder: MCPBridgeHolder
    private let agentLoopService: AgentLoopServiceProtocol
    private let logger: LoggerProtocol

    init(bridgeHolder: MCPBridgeHolder, agentLoopService: AgentLoopServiceProtocol, logger: LoggerProtocol) {
        self.bridgeHolder = bridgeHolder
        self.agentLoopService = agentLoopService
        self.logger = logger
    }

    func streamResponse(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async throws -> Response {
        let completionId = ChatCompletionChunk.makeCompletionId()
        let model = request.model

        var mcpToolServerMap: [String: String] = [:]
        var allTools = request.tools ?? []

        if let mcpBridge = await bridgeHolder.bridge {
            do {
                let mcpTools = try await mcpBridge.listTools()
                for tool in mcpTools {
                    mcpToolServerMap[tool.name] = tool.serverName
                    allTools.append(tool.toOpenAITool())
                }
                logger.debug("Injected \(mcpTools.count) MCP tool(s) into request")
            } catch {
                logger.warn("Failed to list MCP tools: \(error)")
            }
        }

        let frozenTools = allTools
        let frozenMCPToolServerMap = mcpToolServerMap

        let responseStream = AsyncStream<ByteBuffer> { continuation in
            let writer = AgentStreamWriter(
                continuation: continuation,
                completionId: completionId,
                model: model
            )

            let task = Task { [agentLoopService] in
                await agentLoopService.runAgentLoop(
                    request: request,
                    credentials: credentials,
                    allTools: frozenTools,
                    mcpToolServerMap: frozenMCPToolServerMap,
                    writer: writer
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return Response(status: .ok, headers: SSEHeaderBuilder.headers(), body: .init(asyncSequence: responseStream))
    }
}

