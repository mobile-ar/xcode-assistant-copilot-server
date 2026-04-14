import ArgumentParser
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
        let launcher = ServerLauncher(
            port: port,
            logLevel: logLevel,
            configPath: config,
            clientName: App.configuration.commandName ?? "xcode-assistant-copilot-server",
            clientVersion: appVersion
        )
        do {
            try await launcher.run()
        } catch is ServerLaunchError {
            throw ExitCode.failure
        }
    }
}