import Foundation

public enum ConfigurationLoaderError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidJSON(String)
    case validationFailed(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            "Configuration file not found: \(path)"
        case .invalidJSON(let message):
            "Failed to parse configuration JSON: \(message)"
        case .validationFailed(let message):
            "Configuration validation failed: \(message)"
        }
    }
}

public protocol ConfigurationLoaderProtocol: Sendable {
    func load(from path: String?) throws -> ServerConfiguration
}

public struct ConfigurationLoader: ConfigurationLoaderProtocol {
    private let logger: LoggerProtocol
    private let defaultConfigDirectory: String
    private let defaultConfigPath: String

    static let productionConfigDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/xcode-assistant-copilot-server"
    }()

    static let productionConfigPath: String = {
        "\(productionConfigDirectory)/config.json"
    }()

    static let defaultConfigJSON: String = """
    {
      "allowedCliTools" : [],
      "autoApprovePermissions" : [
        "read",
        "mcp"
      ],
      "bodyLimitMiB" : 4,
      "excludedFilePatterns" : [],
      "maxAgentLoopIterations" : 40,
      "mcpServers" : {
        "xcode" : {
          "allowedTools" : [
            "*"
          ],
          "args" : [
            "mcpbridge"
          ],
          "command" : "xcrun",
          "type" : "local"
        }
      },
      "reasoningEffort" : "xhigh",
      "timeouts" : {
        "httpClientTimeoutSeconds" : 300,
        "requestTimeoutSeconds" : 300,
        "streamingEndpointTimeoutSeconds" : 300
      }
    }
    """

    public init(logger: LoggerProtocol) {
        self.logger = logger
        self.defaultConfigDirectory = Self.productionConfigDirectory
        self.defaultConfigPath = Self.productionConfigPath
    }

    init(logger: LoggerProtocol, defaultConfigDirectory: String, defaultConfigPath: String) {
        self.logger = logger
        self.defaultConfigDirectory = defaultConfigDirectory
        self.defaultConfigPath = defaultConfigPath
    }

    public func load(from path: String?) throws -> ServerConfiguration {
        let configPath: String

        if let path {
            configPath = resolveAbsolutePath(path)
            guard FileManager.default.fileExists(atPath: configPath) else {
                logger.warn("No config file at \(configPath), using defaults")
                return .shared
            }
            logger.info("Reading config from \(configPath)")
        } else {
            configPath = defaultConfigPath
            createDefaultConfigIfNeeded()
            logger.info("Reading config from \(configPath)")
        }

        guard let data = FileManager.default.contents(atPath: configPath) else {
            throw ConfigurationLoaderError.fileNotFound(configPath)
        }

        let configuration: ServerConfiguration
        do {
            let decoder = JSONDecoder()
            configuration = try decoder.decode(ServerConfiguration.self, from: data)
        } catch let error as DecodingError {
            throw ConfigurationLoaderError.invalidJSON(describeDecodingError(error))
        } catch {
            throw ConfigurationLoaderError.invalidJSON(error.localizedDescription)
        }

        try validate(configuration)

        backfillMissingKeys(in: data, at: configPath)

        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path
        let resolved = resolveServerPaths(in: configuration, configDir: configDir)

        logConfigurationSummary(resolved)

        return resolved
    }

    func createDefaultConfigIfNeeded() {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: defaultConfigPath) {
            return
        }

        do {
            if !fileManager.fileExists(atPath: defaultConfigDirectory) {
                try fileManager.createDirectory(
                    atPath: defaultConfigDirectory,
                    withIntermediateDirectories: true
                )
            }

            try Self.defaultConfigJSON.write(
                toFile: defaultConfigPath,
                atomically: true,
                encoding: .utf8
            )
            logger.info("Created default config at \(defaultConfigPath)")
        } catch {
            logger.warn("Failed to create default config: \(error)")
        }
    }

    private func resolveAbsolutePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return FileManager.default.currentDirectoryPath + "/" + path
    }

    private func resolveServerPaths(in configuration: ServerConfiguration, configDir: String) -> ServerConfiguration {
        var resolvedServers: [String: MCPServerConfiguration] = [:]

        for (name, server) in configuration.mcpServers {
            guard let args = server.args else {
                resolvedServers[name] = server
                continue
            }

            let resolvedArgs = args.map { arg in
                if arg.hasPrefix("./") || arg.hasPrefix("../") {
                    return configDir + "/" + arg
                }
                return arg
            }

            resolvedServers[name] = MCPServerConfiguration(
                type: server.type,
                command: server.command,
                args: resolvedArgs,
                env: server.env,
                cwd: server.cwd,
                url: server.url,
                headers: server.headers,
                allowedTools: server.allowedTools,
                timeout: server.timeout
            )
        }

        return ServerConfiguration(
            mcpServers: resolvedServers,
            allowedCliTools: configuration.allowedCliTools,
            bodyLimitMiB: configuration.bodyLimitMiB,
            excludedFilePatterns: configuration.excludedFilePatterns,
            reasoningEffort: configuration.reasoningEffort,
            autoApprovePermissions: configuration.autoApprovePermissions,
            timeouts: configuration.timeouts,
            maxAgentLoopIterations: configuration.maxAgentLoopIterations
        )
    }

    private func backfillMissingKeys(in existingData: Data, at configPath: String) {
        guard
            let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
            let defaultData = Self.defaultConfigJSON.data(using: .utf8),
            let defaultJSON = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any]
        else { return }

        var missingKeys: [String] = []
        var merged = existingJSON

        for (key, defaultValue) in defaultJSON where existingJSON[key] == nil {
            merged[key] = defaultValue
            missingKeys.append(key)
        }

        guard !missingKeys.isEmpty else { return }

        do {
            let updatedData = try JSONSerialization.data(
                withJSONObject: merged,
                options: [.prettyPrinted, .sortedKeys]
            )
            try updatedData.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            logger.info("Backfilled missing config keys with defaults: \(missingKeys.sorted().joined(separator: ", "))")
        } catch {
            logger.warn("Failed to backfill missing config keys: \(error)")
        }
    }

    private func validate(_ configuration: ServerConfiguration) throws {
        if configuration.bodyLimitMiB < 1 || configuration.bodyLimitMiB > 100 {
            throw ConfigurationLoaderError.validationFailed(
                "bodyLimitMiB must be between 1 and 100, got \(configuration.bodyLimitMiB)"
            )
        }

        let hasWildcard = configuration.allowedCliTools.contains("*")
        if hasWildcard && configuration.allowedCliTools.count > 1 {
            throw ConfigurationLoaderError.validationFailed(
                "allowedCliTools: use [\"*\"] alone to allow all tools, don't mix with other entries"
            )
        }

        for (name, server) in configuration.mcpServers {
            if server.type == .local || server.type == .stdio {
                guard let command = server.command, !command.isEmpty else {
                    throw ConfigurationLoaderError.validationFailed(
                        "MCP server \"\(name)\" requires a non-empty command"
                    )
                }
            }
            if server.type == .http || server.type == .sse {
                guard let url = server.url, !url.isEmpty else {
                    throw ConfigurationLoaderError.validationFailed(
                        "MCP server \"\(name)\" requires a non-empty url"
                    )
                }
            }
        }
    }

    private func logConfigurationSummary(_ configuration: ServerConfiguration) {
        let mcpCount = configuration.mcpServers.count
        let cliToolsSummary: String
        if configuration.allowedCliTools.contains("*") {
            cliToolsSummary = "all CLI tools allowed"
        } else {
            cliToolsSummary = "\(configuration.allowedCliTools.count) allowed CLI tool(s)"
        }
        logger.info("Loaded \(mcpCount) MCP server(s), \(cliToolsSummary)")

        if let effort = configuration.reasoningEffort {
            logger.info("Reasoning effort: \(effort.rawValue)")
        }
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing key \"\(key.stringValue)\" at \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing value for \(type) at \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            return "Corrupted data: \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
