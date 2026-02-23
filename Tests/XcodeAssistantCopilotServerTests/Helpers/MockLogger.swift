@testable import XcodeAssistantCopilotServer

final class MockLogger: LoggerProtocol, @unchecked Sendable {
    let level: LogLevel
    private(set) var errorMessages: [String] = []
    private(set) var warnMessages: [String] = []
    private(set) var infoMessages: [String] = []
    private(set) var debugMessages: [String] = []

    init(level: LogLevel = .all) {
        self.level = level
    }

    func error(_ message: String) {
        errorMessages.append(message)
    }

    func warn(_ message: String) {
        warnMessages.append(message)
    }

    func info(_ message: String) {
        infoMessages.append(message)
    }

    func debug(_ message: String) {
        debugMessages.append(message)
    }
}
