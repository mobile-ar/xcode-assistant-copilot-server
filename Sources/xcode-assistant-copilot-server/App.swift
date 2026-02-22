import ArgumentParser
import XcodeAssistantCopilotServer

@main
struct App: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-assistant-copilot-server",
        abstract: "OpenAI-compatible proxy server for Xcode, powered by GitHub Copilot",
        version: "1.0.2"
    )

    @Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    @Option(name: .long, help: "Log verbosity: none, error, warning, info, debug, all")
    var logLevel: String = "info"

    @Option(name: .long, help: "Path to JSON config file")
    var config: String?

    mutating func run() async throws {
        guard let level = LogLevel(rawValue: logLevel) else {
            let valid = LogLevel.allCases.map(\.rawValue).joined(separator: ", ")
            print("Invalid log level \"\(logLevel)\". Valid: \(valid)")
            throw ExitCode.failure
        }

        guard port >= 1, port <= 65535 else {
            print("Invalid port \"\(port)\". Must be 1-65535.")
            throw ExitCode.failure
        }

        let logger = Logger(level: level)

        let configLoader = ConfigurationLoader(logger: logger)
        let configuration: ServerConfiguration
        do {
            configuration = try configLoader.load(from: config)
        } catch {
            logger.error("Failed to load configuration: \(error)")
            throw ExitCode.failure
        }

        let processRunner = ProcessRunner()
        let urlSession = URLSessionProvider.configuredSession()
        let deviceFlowService = GitHubDeviceFlowService(logger: logger, session: urlSession)
        let authService = GitHubCLIAuthService(
            processRunner: processRunner,
            logger: logger,
            deviceFlowService: deviceFlowService,
            session: urlSession
        )

        logger.info("Checking authentication...")

        if let storedToken = try? deviceFlowService.loadStoredToken() {
            let masked = String(storedToken.accessToken.prefix(4)) + "..." + String(storedToken.accessToken.suffix(4))
            logger.info("Found stored OAuth token (token: \(masked))")
        } else {
            logger.info("No stored OAuth token found, checking GitHub CLI...")
            do {
                let token = try await authService.getGitHubToken()
                let masked = String(token.prefix(4)) + "..." + String(token.suffix(4))
                logger.info("Authenticated with GitHub CLI (token: \(masked))")
            } catch {
                logger.warn("GitHub CLI authentication not available: \(error)")
                logger.info("Device code flow will be used when a Copilot token is needed.")
            }
        }

        let copilotAPI = CopilotAPIService(logger: logger, session: urlSession)

        var mcpBridge: MCPBridgeServiceProtocol?

        if configuration.hasLocalMCPServers {
            if let (_, serverConfig) = configuration.mcpServers.first(where: {
                $0.value.type == .local || $0.value.type == .stdio
            }) {
                let bridge = MCPBridgeService(serverConfig: serverConfig, logger: logger)
                do {
                    logger.info("Starting MCP bridge...")
                    try await bridge.start()
                    mcpBridge = bridge
                    logger.info("MCP bridge is ready")
                } catch {
                    logger.warn("MCP bridge failed to start: \(error)")
                    logger.warn("Continuing without MCP support")
                }
            }
        }

        let server = CopilotServer(
            port: port,
            logger: logger,
            configuration: configuration,
            authService: authService,
            copilotAPI: copilotAPI,
            mcpBridge: mcpBridge
        )

        do {
            try await server.run()
        } catch {
            logger.error("Server error: \(error)")
            if let bridge = mcpBridge as? MCPBridgeService {
                try? await bridge.stop()
            }
            throw ExitCode.failure
        }
    }
}
