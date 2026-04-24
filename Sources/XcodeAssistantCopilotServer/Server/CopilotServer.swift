import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct CopilotServer: Sendable {
    private let port: Int
    private let logger: LoggerProtocol
    private let configurationStore: ConfigurationStore
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let bridgeHolder: MCPBridgeHolder

    public init(
        port: Int,
        logger: LoggerProtocol,
        configurationStore: ConfigurationStore,
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        bridgeHolder: MCPBridgeHolder
    ) {
        self.port = port
        self.logger = logger
        self.configurationStore = configurationStore
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.bridgeHolder = bridgeHolder
    }

    func makeApplication() -> some ApplicationProtocol {
        let modelFetchCache = ModelFetchCache()

        let healthHandler = HealthHandler(
            bridgeHolder: bridgeHolder,
            authService: authService,
            modelFetchCache: modelFetchCache,
            logger: logger
        )

        let modelsHandler = ModelsHandler(
            authService: authService,
            copilotAPI: copilotAPI,
            modelFetchCache: modelFetchCache,
            configurationStore: configurationStore,
            logger: logger
        )

        let modelEndpointResolver = ModelEndpointResolver(copilotAPI: copilotAPI, logger: logger)
        let reasoningEffortResolver = ReasoningEffortResolver()

        let directStrategy = DirectStreamingChatCompletion(
            copilotAPI: copilotAPI,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            responsesTranslator: ResponsesAPITranslator(logger: logger),
            logger: logger
        )

        let mcpToolExecutor = MCPToolExecutor(
            bridgeHolder: bridgeHolder,
            configurationStore: configurationStore,
            logger: logger
        )
        let agentLoopService = AgentLoopService(
            copilotAPI: copilotAPI,
            mcpToolExecutor: mcpToolExecutor,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            responsesTranslator: ResponsesAPITranslator(logger: logger),
            configurationStore: configurationStore,
            logger: logger
        )
        let agentStrategy = AgentStreamingChatCompletion(
            bridgeHolder: bridgeHolder,
            agentLoopService: agentLoopService,
            logger: logger
        )

        let completionsHandler = ChatCompletionsHandler(
            authService: authService,
            configurationStore: configurationStore,
            bridgeHolder: bridgeHolder,
            directStrategy: directStrategy,
            agentStrategy: agentStrategy,
            logger: logger
        )

        let router = Router(context: AppRequestContext.self)

        router.addMiddleware {
            RequestLoggingMiddleware(logger: logger)
            CORSMiddleware(logger: logger)
            XcodeUserAgentMiddleware(logger: logger)
        }

        var registry = RouteRegistry(router: router)

        registry.get("health") { request, _ in
            try await healthHandler.handle(request: request)
        }

        registry.get("v1/models") { _, _ in
            try await modelsHandler.handle()
        }

        registry.post("v1/chat/completions") { request, _ in
            try await completionsHandler.handle(request: request)
        }

        logger.info("Routes: \(registry.summary())")

        return Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port),
                serverName: "xcode-assistant-copilot-server"
            )
        )
    }

    public func run() async throws {
        logger.info("Starting server on http://127.0.0.1:\(port)")
        let app = makeApplication()

        let isBridgeEnabled = await bridgeHolder.bridge != nil
        if isBridgeEnabled {
            logger.info("MCP bridge enabled (agent mode)")
        } else {
            logger.info("MCP bridge disabled (direct proxy mode)")
        }

        try await app.runService()
    }
}