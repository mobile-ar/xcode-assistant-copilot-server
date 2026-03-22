import Foundation
import Synchronization
import Testing
@testable import XcodeAssistantCopilotServer

private final class CountingProcessRunner: ProcessRunnerProtocol, Sendable {
    private let callCount = Mutex(0)
    private let stdout: String

    init(stdout: String) {
        self.stdout = stdout
    }

    var count: Int { callCount.withLock { $0 } }

    func run(executablePath: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        callCount.withLock { $0 += 1 }
        return ProcessResult(stdout: stdout, stderr: "", exitCode: 0)
    }
}

@Test func detectReturnsFormattedVersionFromXcrunOutput() async {
    let runner = MockProcessRunner(stdout: "Xcode 26.0\nBuild version 17A5241e")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == "Xcode/26.0")
}

@Test func detectParsesOlderXcodeVersion() async {
    let runner = MockProcessRunner(stdout: "Xcode 15.4\nBuild version 15F31d")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == "Xcode/15.4")
}

@Test func detectParsesVersionWithPatchComponent() async {
    let runner = MockProcessRunner(stdout: "Xcode 16.2.1\nBuild version 16C5023a")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == "Xcode/16.2.1")
}

@Test func detectUsesDefaultWhenXcrunThrows() async {
    let runner = MockProcessRunner(throwing: ProcessRunnerError.executableNotFound("/usr/bin/xcrun"))
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == CopilotConstants.defaultEditorVersion)
}

@Test func detectUsesDefaultWhenXcrunFailsWithNonZeroExitCode() async {
    let runner = MockProcessRunner(stdout: "", stderr: "xcrun: error: unable to find utility xcodebuild", exitCode: 1)
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == CopilotConstants.defaultEditorVersion)
}

@Test func detectUsesDefaultWhenOutputIsEmpty() async {
    let runner = MockProcessRunner(stdout: "")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == CopilotConstants.defaultEditorVersion)
}

@Test func detectUsesDefaultWhenOutputHasUnexpectedFormat() async {
    let runner = MockProcessRunner(stdout: "SomethingUnexpected")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == CopilotConstants.defaultEditorVersion)
}

@Test func detectUsesDefaultWhenFirstLineHasOnlyOneWord() async {
    let runner = MockProcessRunner(stdout: "Xcode\nBuild version 17A5241e")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())
    let version = await detector.detect()
    #expect(version == CopilotConstants.defaultEditorVersion)
}

@Test func detectCachesResultAndCallsProcessOnlyOnce() async {
    let runner = CountingProcessRunner(stdout: "Xcode 26.0\nBuild version 17A5241e")
    let detector = XcodeVersionDetector(processRunner: runner, logger: MockLogger())

    let first = await detector.detect()
    let second = await detector.detect()
    let third = await detector.detect()

    #expect(first == "Xcode/26.0")
    #expect(second == "Xcode/26.0")
    #expect(third == "Xcode/26.0")
    #expect(runner.count == 1)
}

@Test func detectDefaultEditorVersionMatchesExpectedFormat() {
    #expect(CopilotConstants.defaultEditorVersion.hasPrefix("Xcode/"))
}