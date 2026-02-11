import Foundation

public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var succeeded: Bool { exitCode == 0 }
}

public protocol ProcessRunnerProtocol: Sendable {
    func run(executablePath: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult
}

extension ProcessRunnerProtocol {
    public func run(executablePath: String, arguments: [String]) async throws -> ProcessResult {
        try await run(executablePath: executablePath, arguments: arguments, environment: nil)
    }
}

public enum ProcessRunnerError: Error, CustomStringConvertible {
    case executableNotFound(String)
    case executionFailed(exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .executableNotFound(let path):
            "Executable not found: \(path)"
        case .executionFailed(let exitCode, let stderr):
            "Process exited with code \(exitCode): \(stderr)"
        }
    }
}

public final class ProcessRunner: ProcessRunnerProtocol {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let environment {
                process.environment = environment
            }

            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = ProcessResult(
                    stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunnerError.executableNotFound(executablePath))
            }
        }
    }
}