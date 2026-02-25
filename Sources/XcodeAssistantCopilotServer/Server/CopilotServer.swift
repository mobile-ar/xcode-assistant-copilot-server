import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

public struct CopilotServer: Sendable {
    private let port: Int
    private let logger: LoggerProtocol
    private let configuration: ServerConfiguration
    private let authService: AuthServiceProtocol
    private let copilotAPI: CopilotAPIServiceProtocol
    private let mcpBridge: MCPBridgeServiceProtocol?

    public init(
        port: Int,
        logger: LoggerProtocol,
        configuration: ServerConfiguration,
        authService: AuthServiceProtocol,
        copilotAPI: CopilotAPIServiceProtocol,
        mcpBridge: MCPBridgeServiceProtocol? = nil
    ) {
        self.port = port
        self.logger = logger
        self.configuration = configuration
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.mcpBridge = mcpBridge
    }

    public func run() async throws {
        let healthHandler = HealthHandler(
            mcpBridge: mcpBridge,
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
            mcpBridge: mcpBridge,
            modelEndpointResolver: modelEndpointResolver,
            reasoningEffortResolver: reasoningEffortResolver,
            configuration: configuration,
            logger: logger
        )

        let router = Router(context: AppRequestContext.self)

        router.addMiddleware {
            CORSMiddleware(logger: logger)
            XcodeUserAgentMiddleware(logger: logger)
        }

        var registry = RouteRegistry(router: router)

        registry.get("health") { request, context in
            try await healthHandler.handle(request: request, context: context)
        }

        registry.get("v1/models") { request, context in
            try await modelsHandler.handle(request: request, context: context)
        }

        registry.post("v1/chat/completions") { request, context in
            try await completionsHandler.handle(request: request, context: context)
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

        if mcpBridge != nil {
            logger.info("MCP bridge enabled (agent mode)")
        } else {
            logger.info("MCP bridge disabled (direct proxy mode)")
        }

        try await app.runService()
    }
}
