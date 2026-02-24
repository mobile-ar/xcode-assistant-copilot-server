import Foundation
import Testing

@testable import XcodeAssistantCopilotServer

@Suite("MCPBridgePIDFile Tests")
struct MCPBridgePIDFileTests {
    private let testDirectory: String

    init() {
        let tempDir = NSTemporaryDirectory()
        self.testDirectory = "\(tempDir)mcp-bridge-pid-tests-\(UUID().uuidString)"
    }

    private func makePIDFile() -> MCPBridgePIDFile {
        MCPBridgePIDFile(directory: testDirectory)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(atPath: testDirectory)
    }

    @Test("Write and read PID file round-trips correctly")
    func writeAndRead() throws {
        let pidFile = makePIDFile()
        defer { cleanup() }

        let expectedPID: Int32 = 12345
        try pidFile.write(pid: expectedPID)
        let readPID = pidFile.read()

        #expect(readPID == expectedPID)
    }

    @Test("Read returns nil when no PID file exists")
    func readReturnsNilWhenMissing() {
        let pidFile = makePIDFile()
        defer { cleanup() }

        let result = pidFile.read()

        #expect(result == nil)
    }

    @Test("Remove deletes the PID file")
    func removeDeletesFile() throws {
        let pidFile = makePIDFile()
        defer { cleanup() }

        try pidFile.write(pid: 99999)
        #expect(pidFile.read() != nil)

        pidFile.remove()

        #expect(pidFile.read() == nil)
    }

    @Test("Remove does not throw when no PID file exists")
    func removeWhenMissing() {
        let pidFile = makePIDFile()
        defer { cleanup() }

        pidFile.remove()
    }

    @Test("Write creates intermediate directories")
    func writeCreatesDirectories() throws {
        let nestedDir = "\(testDirectory)/nested/deeply"
        let pidFile = MCPBridgePIDFile(directory: nestedDir)
        defer { cleanup() }

        try pidFile.write(pid: 42)

        let exists = FileManager.default.fileExists(atPath: "\(nestedDir)/mcp-bridge.pid")
        #expect(exists)
        #expect(pidFile.read() == 42)
    }

    @Test("Write overwrites existing PID file")
    func writeOverwrites() throws {
        let pidFile = makePIDFile()
        defer { cleanup() }

        try pidFile.write(pid: 100)
        #expect(pidFile.read() == 100)

        try pidFile.write(pid: 200)
        #expect(pidFile.read() == 200)
    }

    @Test("isProcessRunning returns true for current process")
    func isProcessRunningForCurrentProcess() {
        let pidFile = makePIDFile()
        defer { cleanup() }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = pidFile.isProcessRunning(pid: currentPID)

        #expect(running)
    }

    @Test("isProcessRunning returns false for non-existent PID")
    func isProcessRunningForNonExistentPID() {
        let pidFile = makePIDFile()
        defer { cleanup() }

        let running = pidFile.isProcessRunning(pid: 999999)

        #expect(!running)
    }

    @Test("Read returns nil for corrupted PID file content")
    func readReturnsNilForCorruptedContent() throws {
        let pidFile = makePIDFile()
        defer { cleanup() }

        try FileManager.default.createDirectory(
            atPath: testDirectory,
            withIntermediateDirectories: true
        )
        let filePath = "\(testDirectory)/mcp-bridge.pid"
        let corruptedData = "not-a-number\n".data(using: .utf8)!
        FileManager.default.createFile(atPath: filePath, contents: corruptedData)

        let result = pidFile.read()

        #expect(result == nil)
    }
}