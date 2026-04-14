import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Suite("ServerLauncher")
struct ServerLauncherTests {

    @Test("throws invalidPort for port 0")
    func runThrowsForPortZero() async {
        let launcher = makeLauncher(port: 0)
        await #expect(throws: ServerLaunchError.invalidPort(0)) {
            try await launcher.run()
        }
    }

    @Test("throws invalidPort for negative port")
    func runThrowsForNegativePort() async {
        let launcher = makeLauncher(port: -1)
        await #expect(throws: ServerLaunchError.invalidPort(-1)) {
            try await launcher.run()
        }
    }

    @Test("throws invalidPort for port above 65535")
    func runThrowsForPortAboveMaximum() async {
        let launcher = makeLauncher(port: 65536)
        await #expect(throws: ServerLaunchError.invalidPort(65536)) {
            try await launcher.run()
        }
    }

    @Test("throws invalidLogLevel for unknown log level string")
    func runThrowsForUnknownLogLevel() async {
        let launcher = makeLauncher(logLevel: "verbose")
        await #expect(throws: ServerLaunchError.invalidLogLevel("verbose")) {
            try await launcher.run()
        }
    }

    @Test("throws invalidLogLevel for empty log level string")
    func runThrowsForEmptyLogLevel() async {
        let launcher = makeLauncher(logLevel: "")
        await #expect(throws: ServerLaunchError.invalidLogLevel("")) {
            try await launcher.run()
        }
    }

    @Test("accepts minimum port value 1")
    func runPassesPortValidationForMinimumPort() async throws {
        let configPath = try writeInvalidConfigFile()
        defer { try? FileManager.default.removeItem(atPath: configPath) }
        let launcher = makeLauncher(port: 1, configPath: configPath)
        await #expect(throws: ServerLaunchError.configurationLoadFailed) {
            try await launcher.run()
        }
    }

    @Test("accepts maximum port value 65535")
    func runPassesPortValidationForMaximumPort() async throws {
        let configPath = try writeInvalidConfigFile()
        defer { try? FileManager.default.removeItem(atPath: configPath) }
        let launcher = makeLauncher(port: 65535, configPath: configPath)
        await #expect(throws: ServerLaunchError.configurationLoadFailed) {
            try await launcher.run()
        }
    }

    @Test("accepts all valid log levels", arguments: ["none", "error", "warning", "info", "debug", "all"])
    func runPassesLogLevelValidationForLevel(_ level: String) async throws {
        let configPath = try writeInvalidConfigFile()
        defer { try? FileManager.default.removeItem(atPath: configPath) }
        let launcher = makeLauncher(logLevel: level, configPath: configPath)
        await #expect(throws: ServerLaunchError.configurationLoadFailed) {
            try await launcher.run()
        }
    }

    private func makeLauncher(
        port: Int = 8080,
        logLevel: String = "info",
        configPath: String? = nil
    ) -> ServerLauncher {
        ServerLauncher(
            port: port,
            logLevel: logLevel,
            configPath: configPath,
            clientName: "test-client",
            clientVersion: "0.0.0"
        )
    }

    private func writeInvalidConfigFile() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-config-\(UUID().uuidString).json")
            .path
        try "{ invalid json }".write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}