import Darwin
import Foundation

public enum ServerLaunchError: Error, Sendable, Equatable {
    case invalidPort(Int)
    case invalidLogLevel(String)
    case configurationLoadFailed
}

public struct ServerLauncher: Sendable {
    private let port: Int
    private let logLevel: String
    private let configPath: String?
    private let clientName: String
    private let clientVersion: String

    public init(
        port: Int,
        logLevel: String,
        configPath: String?,
        clientName: String,
        clientVersion: String
    ) {
        self.port = port
        self.logLevel = logLevel
        self.configPath = configPath
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    public func run() async throws {
        try validatePort()
        let logger = try buildLogger()
        let configContext = try await loadConfiguration(logger: logger)
        let pidFile = MCPBridgePIDFile()
        await cleanupOrphanedProcesses(logger: logger, pidFile: pidFile)
        let configuration = await configContext.store.current()
        let coreServices = await assembleCoreServices(
            configuration: configuration,
            configStore: configContext.store,
            logger: logger
        )
        await probeAuthentication(coreServices: coreServices, logger: logger)
        let bridgeHolder = await startMCPBridge(
            configuration: configuration,
            coreServices: coreServices,
            logger: logger,
            pidFile: pidFile
        )
        let signalHandler = setupSignalHandling(logger: logger, bridgeHolder: bridgeHolder)
        let server = buildServer(
            configStore: configContext.store,
            coreServices: coreServices,
            bridgeHolder: bridgeHolder,
            logger: logger
        )
        await runEventLoop(
            server: server,
            configContext: configContext,
            bridgeHolder: bridgeHolder,
            coreServices: coreServices,
            logger: logger,
            pidFile: pidFile,
            signalHandler: signalHandler
        )
        if let bridge = await bridgeHolder.bridge {
            logger.info("Stopping MCP bridge...")
            try? await bridge.stop()
            logger.info("MCP bridge stopped")
        }
    }

    private func validatePort() throws {
        guard port >= 1, port <= 65535 else {
            print("Invalid port \"\(port)\". Must be 1-65535.")
            throw ServerLaunchError.invalidPort(port)
        }
    }

    private func buildLogger() throws -> Logger {
        guard let level = LogLevel(rawValue: logLevel) else {
            let valid = LogLevel.allCases.map(\.rawValue).joined(separator: ", ")
            print("Invalid log level \"\(logLevel)\". Valid: \(valid)")
            throw ServerLaunchError.invalidLogLevel(logLevel)
        }
        return Logger(level: level)
    }

    private func loadConfiguration(logger: LoggerProtocol) async throws -> ConfigurationContext {
        let interactiveLoader = ConfigurationLoader(logger: logger, interactive: true)
        let configuration: ServerConfiguration
        do {
            configuration = try interactiveLoader.load(from: configPath)
        } catch {
            logger.error("Failed to load configuration: \(error)")
            throw ServerLaunchError.configurationLoadFailed
        }
        let store = ConfigurationStore(initial: configuration)
        let watchPath = configPath ?? ConfigurationLoader.productionConfigPath
        let watcherLoader = ConfigurationLoader(logger: logger, interactive: false)
        let watcher = ConfigurationWatcher(path: watchPath, loader: watcherLoader, logger: logger)
        await watcher.start()
        return ConfigurationContext(store: store, watcher: watcher)
    }

    private func cleanupOrphanedProcesses(logger: LoggerProtocol, pidFile: MCPBridgePIDFileProtocol) async {
        let cleaner = OrphanedProcessCleaner(pidFile: pidFile, logger: logger)
        await cleaner.cleanupIfNeeded()
    }

    private func assembleCoreServices(
        configuration: ServerConfiguration,
        configStore: ConfigurationStore,
        logger: LoggerProtocol
    ) async -> CoreServices {
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
        let copilotAPI = CopilotAPIService(
            httpClient: httpClient,
            logger: logger,
            configurationStore: configStore,
            requestHeaders: requestHeaders
        )
        return CoreServices(
            processRunner: processRunner,
            httpClient: httpClient,
            requestHeaders: requestHeaders,
            authService: authService,
            deviceFlowService: deviceFlowService,
            copilotAPI: copilotAPI
        )
    }

    private func probeAuthentication(coreServices: CoreServices, logger: LoggerProtocol) async {
        logger.info("Checking authentication...")
        if let storedToken = try? coreServices.deviceFlowService.loadStoredToken() {
            let masked = String(storedToken.accessToken.prefix(4)) + "..." + String(storedToken.accessToken.suffix(4))
            logger.info("Found stored OAuth token (token: \(masked))")
        } else {
            logger.info("No stored OAuth token found, checking GitHub CLI...")
            do {
                let token = try await coreServices.authService.getGitHubToken()
                let masked = String(token.prefix(4)) + "..." + String(token.suffix(4))
                logger.info("Authenticated with GitHub CLI (token: \(masked))")
            } catch {
                logger.warn("GitHub CLI authentication not available: \(error)")
                logger.info("Device code flow will be used when a Copilot token is needed.")
            }
        }
    }

    private func startMCPBridge(
        configuration: ServerConfiguration,
        coreServices: CoreServices,
        logger: LoggerProtocol,
        pidFile: MCPBridgePIDFileProtocol
    ) async -> MCPBridgeHolder {
        let bridgeHolder = MCPBridgeHolder()
        await applyBridge(from: configuration, to: bridgeHolder, coreServices: coreServices, logger: logger, pidFile: pidFile)
        return bridgeHolder
    }

    private func applyBridge(
        from configuration: ServerConfiguration,
        to holder: MCPBridgeHolder,
        coreServices: CoreServices,
        logger: LoggerProtocol,
        pidFile: MCPBridgePIDFileProtocol
    ) async {
        guard let bridge = MCPBridgeFactory.make(
            from: configuration,
            logger: logger,
            httpClient: coreServices.httpClient,
            pidFile: pidFile,
            clientName: clientName,
            clientVersion: clientVersion,
            processRunner: coreServices.processRunner
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

    private func setupSignalHandling(logger: LoggerProtocol, bridgeHolder: MCPBridgeHolder) -> SignalHandler {
        let signalHandler = SignalHandler(logger: logger)
        signalHandler.monitorSignals { signal in
            logger.info("Stopping MCP bridge due to signal \(signal)...")
            if let bridge = await bridgeHolder.bridge {
                try? await bridge.stop()
            }
        }
        return signalHandler
    }

    private func buildServer(
        configStore: ConfigurationStore,
        coreServices: CoreServices,
        bridgeHolder: MCPBridgeHolder,
        logger: LoggerProtocol
    ) -> CopilotServer {
        CopilotServer(
            port: port,
            logger: logger,
            configurationStore: configStore,
            authService: coreServices.authService,
            copilotAPI: coreServices.copilotAPI,
            bridgeHolder: bridgeHolder
        )
    }

    private func runEventLoop(
        server: CopilotServer,
        configContext: ConfigurationContext,
        bridgeHolder: MCPBridgeHolder,
        coreServices: CoreServices,
        logger: LoggerProtocol,
        pidFile: MCPBridgePIDFileProtocol,
        signalHandler: SignalHandler
    ) async {
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

            group.addTask { [self] in
                let configStream = await configContext.watcher.changes()
                for await newConfig in configStream {
                    let decision = ConfigurationReloadDecision.decide(
                        from: await configContext.store.current(),
                        to: newConfig
                    )
                    switch decision {
                    case .hotReload(let updated):
                        await configContext.store.update(updated)
                        logger.info("Configuration hot-reloaded successfully")

                    case .mcpRestart(let updated):
                        logger.info("MCP servers changed — restarting MCP bridge...")
                        if let bridge = await bridgeHolder.bridge {
                            try? await bridge.stop()
                            await bridgeHolder.setBridge(nil)
                        }
                        await self.applyBridge(
                            from: updated,
                            to: bridgeHolder,
                            coreServices: coreServices,
                            logger: logger,
                            pidFile: pidFile
                        )
                        await configContext.store.update(updated)
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
                    await configContext.watcher.stop()
                    group.cancelAll()
                    break
                }
            }
        }
    }
}
