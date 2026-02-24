import Foundation
import Testing

@testable import XcodeAssistantCopilotServer

@Suite("OrphanedProcessCleaner Tests")
struct OrphanedProcessCleanerTests {

    @Test("Does nothing when no PID file exists")
    func noPIDFile() {
        let mockPIDFile = MockMCPBridgePIDFile()
        let logger = MockLogger()
        let cleaner = OrphanedProcessCleaner(pidFile: mockPIDFile, logger: logger)

        cleaner.cleanupIfNeeded()

        #expect(mockPIDFile.readCallCount == 1)
        #expect(mockPIDFile.removeCallCount == 0)
        #expect(mockPIDFile.isProcessRunningCallCount == 0)
    }

    @Test("Removes stale PID file when process is no longer running")
    func staleProcessNotRunning() {
        let mockPIDFile = MockMCPBridgePIDFile()
        mockPIDFile.storedPID = 12345
        mockPIDFile.processRunning = false
        let logger = MockLogger()
        let cleaner = OrphanedProcessCleaner(pidFile: mockPIDFile, logger: logger)

        cleaner.cleanupIfNeeded()

        #expect(mockPIDFile.readCallCount == 1)
        #expect(mockPIDFile.isProcessRunningCallCount == 1)
        #expect(mockPIDFile.isProcessRunningReceivedPID == 12345)
        #expect(mockPIDFile.removeCallCount == 1)
        #expect(logger.infoMessages.contains { $0.contains("no longer running") })
    }

    @Test("Terminates orphaned process that is still running and removes PID file")
    func terminatesOrphanedProcess() {
        let mockPIDFile = MockMCPBridgePIDFile()
        mockPIDFile.storedPID = 99999
        mockPIDFile.processRunning = true
        mockPIDFile.processBecomesDeadAfterCheck = 1
        let logger = MockLogger()
        let cleaner = OrphanedProcessCleaner(pidFile: mockPIDFile, logger: logger)

        cleaner.cleanupIfNeeded()

        #expect(mockPIDFile.readCallCount == 1)
        #expect(mockPIDFile.isProcessRunningCallCount >= 2)
        #expect(mockPIDFile.removeCallCount == 1)
        #expect(logger.warnMessages.contains { $0.contains("Orphaned MCP bridge process detected") })
        #expect(logger.infoMessages.contains { $0.contains("cleaned up") })
    }

    @Test("Sends SIGKILL when process does not terminate gracefully")
    func sendsKillWhenProcessDoesNotTerminate() {
        let mockPIDFile = MockMCPBridgePIDFile()
        mockPIDFile.storedPID = 88888
        mockPIDFile.processRunning = true
        mockPIDFile.processBecomesDeadAfterCheck = .max
        let logger = MockLogger()
        let cleaner = OrphanedProcessCleaner(pidFile: mockPIDFile, logger: logger)

        cleaner.cleanupIfNeeded()

        #expect(mockPIDFile.removeCallCount == 1)
        #expect(logger.warnMessages.contains { $0.contains("SIGKILL") })
    }

    @Test("Logs PID correctly when orphaned process found")
    func logsPIDCorrectly() {
        let mockPIDFile = MockMCPBridgePIDFile()
        mockPIDFile.storedPID = 54321
        mockPIDFile.processRunning = false
        let logger = MockLogger()
        let cleaner = OrphanedProcessCleaner(pidFile: mockPIDFile, logger: logger)

        cleaner.cleanupIfNeeded()

        #expect(logger.infoMessages.contains { $0.contains("54321") })
    }
}

final class MockMCPBridgePIDFile: MCPBridgePIDFileProtocol, @unchecked Sendable {
    var storedPID: Int32?
    var processRunning: Bool = false
    var processBecomesDeadAfterCheck: Int = 0

    private(set) var writeCallCount = 0
    private(set) var writtenPID: Int32?
    private(set) var readCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var isProcessRunningCallCount = 0
    private(set) var isProcessRunningReceivedPID: Int32?

    func write(pid: Int32) throws {
        writeCallCount += 1
        writtenPID = pid
        storedPID = pid
    }

    func read() -> Int32? {
        readCallCount += 1
        return storedPID
    }

    func remove() {
        removeCallCount += 1
        storedPID = nil
    }

    func isProcessRunning(pid: Int32) -> Bool {
        isProcessRunningCallCount += 1
        isProcessRunningReceivedPID = pid
        if isProcessRunningCallCount > processBecomesDeadAfterCheck {
            return false
        }
        return processRunning
    }
}