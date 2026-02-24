import Foundation

public protocol OrphanedProcessCleanerProtocol: Sendable {
    func cleanupIfNeeded()
}

public struct OrphanedProcessCleaner: OrphanedProcessCleanerProtocol, Sendable {
    private let pidFile: MCPBridgePIDFileProtocol
    private let logger: LoggerProtocol

    public init(pidFile: MCPBridgePIDFileProtocol, logger: LoggerProtocol) {
        self.pidFile = pidFile
        self.logger = logger
    }

    public func cleanupIfNeeded() {
        guard let stalePID = pidFile.read() else {
            logger.debug("No stale MCP bridge PID file found")
            return
        }

        logger.info("Found stale MCP bridge PID file (PID: \(stalePID))")

        guard pidFile.isProcessRunning(pid: stalePID) else {
            logger.info("Orphaned PID \(stalePID) is no longer running, removing stale PID file")
            pidFile.remove()
            return
        }

        logger.warn("Orphaned MCP bridge process detected (PID: \(stalePID)), terminating...")

        kill(stalePID, SIGTERM)

        var terminated = false
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.1)
            if !pidFile.isProcessRunning(pid: stalePID) {
                terminated = true
                break
            }
        }

        if !terminated {
            logger.warn("Orphaned MCP bridge process did not terminate gracefully, sending SIGKILL (PID: \(stalePID))")
            kill(stalePID, SIGKILL)
        }

        logger.info("Orphaned MCP bridge process cleaned up (PID: \(stalePID))")
        pidFile.remove()
    }
}