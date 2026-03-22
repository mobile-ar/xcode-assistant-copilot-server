import ArgumentParser
import Darwin
import XcodeAssistantCopilotServer

@main
struct App: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-assistant-copilot-server",
        abstract: "OpenAI-compatible proxy server for Xcode, powered by GitHub Copilot",
        version: appVersion
    )

    @Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    @Option(name: .long, help: "Log verbosity: none, error, warning, info, debug, all")
    var logLevel: String = "info"

    @Option(name: .long, help: "Path to JSON config file (default: ~/.config/xcode-assistant-copilot-server/config.json)")
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

        let configurationStore = ConfigurationStore(initial: configuration)

        let watchPath = config ?? ConfigurationLoader.productionConfigPath
        let watcher = ConfigurationWatcher(path: watchPath, loader: configLoader, logger: logger)
        await watcher.start()

        let pidFile = MCPBridgePIDFile()
        let orphanCleaner = OrphanedProcessCleaner(pidFile: pidFile, logger: logger)
        await orphanCleaner.cleanupIfNeeded()

        let processRunner = ProcessRunner()
        let httpClient = HTTPClient(timeoutIntervalForRequest: configuration.timeouts.httpClientTimeoutSeconds)
        let editorVersion = await XcodeVersionDetector(processRunner: processRunner, logger: logger).detect()
        let requestHeaders = CopilotRequestHeaders(editorVersion: editorVersion)
        let deviceFlowService = GitHubDeviceFlowService(logger: logger, httpClient: httpClient)
        let authService = GitHubCLIAuthService(
            processRunner: processRunner,
            logger: logger,
            deviceFlowService: deviceFlowService,
            httpClient: httpClient,
            requestHeaders: requestHeaders
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

        let copilotAPI = CopilotAPIService(
            httpClient: httpClient,
            logger: logger,
            configurationStore: configurationStore,
            requestHeaders: requestHeaders
        )

        let clientName = App.configuration.commandName ?? "xcode-assistant-copilot-server"
        let bridgeHolder = MCPBridgeHolder()

        await applyBridge(
            from: configuration,
            to: bridgeHolder,
            logger: logger,
            httpClient: httpClient,
            pidFile: pidFile,
            clientName: clientName,
            clientVersion: appVersion,
            processRunner: processRunner
        )

        let signalHandler = SignalHandler(logger: logger)
        signalHandler.monitorSignals { signal in
            logger.info("Stopping MCP bridge due to signal \(signal)...")
            if let bridge = await bridgeHolder.bridge {
                try? await bridge.stop()
            }
        }

        let server = CopilotServer(
            port: port,
            logger: logger,
            configurationStore: configurationStore,
            authService: authService,
            copilotAPI: copilotAPI,
            bridgeHolder: bridgeHolder
        )

        // The task group uses Bool to identify which task completed first.
        // The server task returns true; the watcher task returns false.
        // As soon as the server exits (signal or error) we stop the watcher
        // and cancel all remaining tasks so the process can exit cleanly.
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await server.run()
                } catch {
                    logger.error("Server error: \(error)")
                }
                return true
            }

            group.addTask {
                let configStream = await watcher.changes()
                for await newConfig in configStream {
                    let decision = ConfigurationReloadDecision.decide(
                        from: await configurationStore.current(),
                        to: newConfig
                    )
                    switch decision {
                    case .hotReload(let updated):
                        await configurationStore.update(updated)
                        logger.info("Configuration hot-reloaded successfully")

                    case .mcpRestart(let updated):
                        logger.info("MCP servers changed — restarting MCP bridge...")

                        if let bridge = await bridgeHolder.bridge {
                            try? await bridge.stop()
                            await bridgeHolder.setBridge(nil)
                        }

                        await applyBridge(
                            from: updated,
                            to: bridgeHolder,
                            logger: logger,
                            httpClient: httpClient,
                            pidFile: pidFile,
                            clientName: clientName,
                            clientVersion: appVersion,
                            processRunner: processRunner
                        )
                        await configurationStore.update(updated)

                        if await bridgeHolder.bridge != nil {
                            logger.info("MCP bridge restarted successfully")
                        }

                    case .requiresManualRestart(let reason):
                        logger.warn("Configuration change requires a manual restart: \(reason)")
                        logger.warn("Stopping server. Please restart to apply the new configuration.")
                        Darwin.exit(0)
                    }
                }
                return false
            }

            // Drain completed tasks. The moment the server task finishes
            // (true), stop the watcher — which finishes its stream — then
            // cancel any tasks still running.
            for await isServerTask in group {
                if isServerTask {
                    await watcher.stop()
                    group.cancelAll()
                    break
                }
            }
        }

        if let bridge = await bridgeHolder.bridge {
            logger.info("Stopping MCP bridge...")
            try? await bridge.stop()
            logger.info("MCP bridge stopped")
        }
    }
}

private func applyBridge(
    from configuration: ServerConfiguration,
    to holder: MCPBridgeHolder,
    logger: LoggerProtocol,
    httpClient: HTTPClientProtocol,
    pidFile: MCPBridgePIDFileProtocol,
    clientName: String,
    clientVersion: String,
    processRunner: ProcessRunnerProtocol
) async {
    guard let bridge = MCPBridgeFactory.make(
        from: configuration,
        logger: logger,
        httpClient: httpClient,
        pidFile: pidFile,
        clientName: clientName,
        clientVersion: clientVersion,
        processRunner: processRunner
    ) else {
        return
    }

    do {
        logger.info("Starting MCP bridge...")
        try await bridge.start()
        await holder.setBridge(bridge)
        logger.info("MCP bridge is ready")
    } catch {
        logger.warn("MCP bridge failed to start: \(error)")
        logger.warn("Continuing without MCP support")
    }
}
