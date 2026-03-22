import Foundation

public protocol XcodeVersionDetectorProtocol: Sendable {
    func detect() async -> String
}

public actor XcodeVersionDetector: XcodeVersionDetectorProtocol {
    private let processRunner: ProcessRunnerProtocol
    private let logger: LoggerProtocol
    private var cached: String?

    public init(processRunner: ProcessRunnerProtocol, logger: LoggerProtocol) {
        self.processRunner = processRunner
        self.logger = logger
    }

    public func detect() async -> String {
        if let cached {
            return cached
        }
        let version = await detectFromSystem()
        cached = version
        return version
    }

    private func detectFromSystem() async -> String {
        let result: ProcessResult
        do {
            result = try await processRunner.run(
                executablePath: "/usr/bin/xcrun",
                arguments: ["xcodebuild", "-version"]
            )
        } catch {
            logger.warn("Failed to run xcrun to detect Xcode version: \(error). Using default: \(CopilotConstants.defaultEditorVersion)")
            return CopilotConstants.defaultEditorVersion
        }

        guard result.succeeded else {
            logger.warn("xcrun xcodebuild -version exited with code \(result.exitCode). Using default: \(CopilotConstants.defaultEditorVersion)")
            return CopilotConstants.defaultEditorVersion
        }

        return parseEditorVersion(from: result.stdout)
    }

    private func parseEditorVersion(from output: String) -> String {
        let firstLine = output.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            logger.warn("Unexpected xcrun output format: \"\(firstLine)\". Using default: \(CopilotConstants.defaultEditorVersion)")
            return CopilotConstants.defaultEditorVersion
        }
        return "\(parts[0])/\(parts[1])"
    }
}