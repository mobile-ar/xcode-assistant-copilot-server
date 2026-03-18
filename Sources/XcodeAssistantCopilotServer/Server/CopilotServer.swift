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

    public func run() async throws {
        let healthHandler = HealthHandler(
            bridgeHolder: bridgeHolder,
            logger: logger
        )

        let modelsHandler = ModelsHandler(
            authService: authService,
            copilotAPI: copilotAPI,
            logger: logger
        )

        let modelEndpointResolver = ModelEndpointResolver(copilotAPI: copilotAPI, logger: logger)
        let reasoningEffortResolver = ReasoningEffortResolver()

        let completionsHandler = ChatCompletionsHandler(
            authService: authService,
            copilotAPI: copilotAPI,
            bridgeHolder: bridgeHolder,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            configurationStore: configurationStore,
            logger: logger
        )

        let router = Router(context: AppRequestContext.self)

        router.addMiddleware {
            RequestLoggingMiddleware(logger: logger)
            CORSMiddleware(logger: logger)
            XcodeUserAgentMiddleware(logger: logger)
        }

        var registry = RouteRegistry(router: router)

        registry.get("health") { _, _ in
            try await healthHandler.handle()
        }

        registry.get("v1/models") { _, _ in
            try await modelsHandler.handle()
        }

        registry.post("v1/chat/completions") { request, _ in
            try await completionsHandler.handle(request: request)
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port),
                serverName: "xcode-assistant-copilot-server"
            )
        )

        logger.info("Starting server on http://127.0.0.1:\(port)")
        logger.info("Routes: \(registry.summary())")

        let isBridgeEnabled = await bridgeHolder.bridge != nil
        if isBridgeEnabled {
            logger.info("MCP bridge enabled (agent mode)")
        } else {
            logger.info("MCP bridge disabled (direct proxy mode)")
        }

        try await app.runService()
    }
}
