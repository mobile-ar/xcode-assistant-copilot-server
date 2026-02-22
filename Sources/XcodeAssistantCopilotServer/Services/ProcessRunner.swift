import Foundation
import Synchronization

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

            let state = Mutex(PipeCollectionState())

            let resumeIfComplete: @Sendable (Process) -> Void = { process in
                let snapshot = state.withLock { s -> PipeCollectionState? in
                    guard s.stdoutDone && s.stderrDone && s.processTerminated && !s.resumed else {
                        return nil
                    }
                    s.resumed = true
                    return s
                }

                guard let snapshot else { return }

                let stdout = String(data: snapshot.stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: snapshot.stderrData, encoding: .utf8) ?? ""

                let result = ProcessResult(
                    stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.withLock { $0.stdoutDone = true }
                    resumeIfComplete(process)
                } else {
                    state.withLock { $0.stdoutData.append(data) }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.withLock { $0.stderrDone = true }
                    resumeIfComplete(process)
                } else {
                    state.withLock { $0.stderrData.append(data) }
                }
            }

            process.terminationHandler = { terminatedProcess in
                state.withLock { $0.processTerminated = true }
                resumeIfComplete(terminatedProcess)
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                state.withLock { $0.resumed = true }
                continuation.resume(throwing: ProcessRunnerError.executableNotFound(executablePath))
            }
        }
    }
}

private struct PipeCollectionState {
    var stdoutData = Data()
    var stderrData = Data()
    var stdoutDone = false
    var stderrDone = false
    var processTerminated = false
    var resumed = false
}