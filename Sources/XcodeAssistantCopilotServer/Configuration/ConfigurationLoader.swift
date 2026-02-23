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

    public init(logger: LoggerProtocol) {
        self.logger = logger
    }

    public func load(from path: String?) throws -> ServerConfiguration {
        guard let path else {
            logger.info("No config file specified, using defaults")
            return .shared
        }

        let absolutePath = resolveAbsolutePath(path)

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            logger.warn("No config file at \(absolutePath), using defaults")
            return .shared
        }

        logger.info("Reading config from \(absolutePath)")

        guard let data = FileManager.default.contents(atPath: absolutePath) else {
            throw ConfigurationLoaderError.fileNotFound(absolutePath)
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

        let configDir = URL(fileURLWithPath: absolutePath).deletingLastPathComponent().path
        let resolved = resolveServerPaths(in: configuration, configDir: configDir)

        logConfigurationSummary(resolved)

        return resolved
    }

    private func resolveAbsolutePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return FileManager.default.currentDirectoryPath + "/" + path
    }

    private func resolveServerPaths(
        in configuration: ServerConfiguration,
        configDir: String
    ) -> ServerConfiguration {
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
            autoApprovePermissions: configuration.autoApprovePermissions
        )
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
