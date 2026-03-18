@testable import XcodeAssistantCopilotServer

struct MockProcessRunner: ProcessRunnerProtocol {
    let result: ProcessResult
    let shouldThrow: Error?

    init(result: ProcessResult, shouldThrow: Error? = nil) {
        self.result = result
        self.shouldThrow = shouldThrow
    }

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.result = ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
        self.shouldThrow = nil
    }

    init(throwing error: Error) {
        self.result = ProcessResult(stdout: "", stderr: "", exitCode: 1)
        self.shouldThrow = error
    }

    func run(executablePath: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        if let error = shouldThrow {
            throw error
        }
        return result
    }
}
