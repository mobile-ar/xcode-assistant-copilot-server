import Testing
import Foundation
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

@Test func processResultSucceeded() {
    let success = ProcessResult(stdout: "output", stderr: "", exitCode: 0)
    #expect(success.succeeded == true)

    let failure = ProcessResult(stdout: "", stderr: "error", exitCode: 1)
    #expect(failure.succeeded == false)
}

@Test func processResultSucceededWithZeroExitCode() {
    let result = ProcessResult(stdout: "hello", stderr: "", exitCode: 0)
    #expect(result.succeeded == true)
    #expect(result.stdout == "hello")
    #expect(result.stderr == "")
    #expect(result.exitCode == 0)
}

@Test func processResultFailedWithNonZeroExitCode() {
    let result = ProcessResult(stdout: "", stderr: "something went wrong", exitCode: 127)
    #expect(result.succeeded == false)
    #expect(result.exitCode == 127)
    #expect(result.stderr == "something went wrong")
}

@Test func processResultFailedWithExitCodeOne() {
    let result = ProcessResult(stdout: "", stderr: "fail", exitCode: 1)
    #expect(result.succeeded == false)
}

@Test func processResultFailedWithNegativeExitCode() {
    let result = ProcessResult(stdout: "", stderr: "", exitCode: -1)
    #expect(result.succeeded == false)
}

@Test func processResultPreservesStdoutAndStderr() {
    let result = ProcessResult(stdout: "some output", stderr: "some warning", exitCode: 0)
    #expect(result.stdout == "some output")
    #expect(result.stderr == "some warning")
    #expect(result.succeeded == true)
}

@Test func mockProcessRunnerReturnsConfiguredResult() async throws {
    let mock = MockProcessRunner(stdout: "mocked output", stderr: "", exitCode: 0)
    let result = try await mock.run(executablePath: "/usr/bin/echo", arguments: ["hello"])
    #expect(result.stdout == "mocked output")
    #expect(result.succeeded == true)
}

@Test func mockProcessRunnerThrowsConfiguredError() async {
    let mock = MockProcessRunner(throwing: ProcessRunnerError.executableNotFound("/nonexistent"))
    do {
        _ = try await mock.run(executablePath: "/nonexistent", arguments: [])
        Issue.record("Expected error to be thrown")
    } catch {
        #expect(error is ProcessRunnerError)
    }
}

@Test func mockProcessRunnerAcceptsEnvironment() async throws {
    let mock = MockProcessRunner(stdout: "env result", stderr: "", exitCode: 0)
    let result = try await mock.run(
        executablePath: "/usr/bin/env",
        arguments: [],
        environment: ["MY_VAR": "hello"]
    )
    #expect(result.stdout == "env result")
    #expect(result.succeeded == true)
}

@Test func mockProcessRunnerDefaultExtensionOmitsEnvironment() async throws {
    let mock = MockProcessRunner(stdout: "default", stderr: "", exitCode: 0)
    let result = try await mock.run(executablePath: "/usr/bin/true", arguments: ["arg1", "arg2"])
    #expect(result.stdout == "default")
    #expect(result.succeeded == true)
}

@Test func processRunnerErrorDescriptions() {
    let notFound = ProcessRunnerError.executableNotFound("/usr/local/bin/missing")
    #expect(notFound.description.contains("/usr/local/bin/missing"))
    #expect(notFound.description.contains("not found"))

    let failed = ProcessRunnerError.executionFailed(exitCode: 42, stderr: "something broke")
    #expect(failed.description.contains("42"))
    #expect(failed.description.contains("something broke"))
}

@Test func processRunnerErrorExecutableNotFoundDescription() {
    let error = ProcessRunnerError.executableNotFound("/path/to/tool")
    #expect(error.description == "Executable not found: /path/to/tool")
}

@Test func processRunnerErrorExecutionFailedDescription() {
    let error = ProcessRunnerError.executionFailed(exitCode: 2, stderr: "No such file")
    #expect(error.description == "Process exited with code 2: No such file")
}

@Test func processRunnerCanRunRealEcho() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(executablePath: "/bin/echo", arguments: ["hello", "world"])
    #expect(result.succeeded == true)
    #expect(result.stdout == "hello world")
    #expect(result.exitCode == 0)
}

@Test func processRunnerCanRunRealTrue() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(executablePath: "/usr/bin/true", arguments: [])
    #expect(result.succeeded == true)
    #expect(result.exitCode == 0)
}

@Test func processRunnerCanRunRealFalse() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(executablePath: "/usr/bin/false", arguments: [])
    #expect(result.succeeded == false)
    #expect(result.exitCode == 1)
}

@Test func processRunnerThrowsForNonexistentExecutable() async {
    let runner = ProcessRunner()
    do {
        _ = try await runner.run(executablePath: "/nonexistent/path/to/binary", arguments: [])
        Issue.record("Expected error for nonexistent executable")
    } catch {
        #expect(error is ProcessRunnerError)
    }
}

@Test func processRunnerCapturesStderr() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(
        executablePath: "/bin/sh",
        arguments: ["-c", "echo error_output >&2; exit 1"]
    )
    #expect(result.succeeded == false)
    #expect(result.stderr == "error_output")
    #expect(result.exitCode == 1)
}

@Test func processRunnerCapturesBothStdoutAndStderr() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(
        executablePath: "/bin/sh",
        arguments: ["-c", "echo stdout_line; echo stderr_line >&2; exit 0"]
    )
    #expect(result.succeeded == true)
    #expect(result.stdout == "stdout_line")
    #expect(result.stderr == "stderr_line")
}

@Test func processRunnerWithEnvironment() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(
        executablePath: "/bin/sh",
        arguments: ["-c", "echo $TEST_VAR_XCODE_COPILOT"],
        environment: [
            "TEST_VAR_XCODE_COPILOT": "custom_value",
            "PATH": "/usr/bin:/bin",
        ]
    )
    #expect(result.succeeded == true)
    #expect(result.stdout == "custom_value")
}

@Test func processRunnerHandlesEmptyOutput() async throws {
    let runner = ProcessRunner()
    let result = try await runner.run(executablePath: "/usr/bin/true", arguments: [])
    #expect(result.stdout == "")
    #expect(result.stderr == "")
}

@Test func mockProcessRunnerWithFailureResult() async throws {
    let mock = MockProcessRunner(
        result: ProcessResult(stdout: "partial output", stderr: "critical error", exitCode: 137)
    )
    let result = try await mock.run(executablePath: "/usr/bin/something", arguments: ["-v"])
    #expect(result.succeeded == false)
    #expect(result.exitCode == 137)
    #expect(result.stdout == "partial output")
    #expect(result.stderr == "critical error")
}