@testable import XcodeAssistantCopilotServer
import Synchronization

final class MockLogger: LoggerProtocol, Sendable {
    private struct State {
        var errorMessages: [String] = []
        var warnMessages: [String] = []
        var infoMessages: [String] = []
        var debugMessages: [String] = []
    }

    private let state = Mutex(State())
    let level: LogLevel

    init(level: LogLevel = .all) {
        self.level = level
    }

    var errorMessages: [String] { state.withLock { $0.errorMessages } }
    var warnMessages: [String] { state.withLock { $0.warnMessages } }
    var infoMessages: [String] { state.withLock { $0.infoMessages } }
    var debugMessages: [String] { state.withLock { $0.debugMessages } }

    func error(_ message: @autoclosure () -> String) {
        state.withLock { $0.errorMessages.append(message()) }
    }

    func warn(_ message: @autoclosure () -> String) {
        state.withLock { $0.warnMessages.append(message()) }
    }

    func info(_ message: @autoclosure () -> String) {
        state.withLock { $0.infoMessages.append(message()) }
    }

    func debug(_ message: @autoclosure () -> String) {
        state.withLock { $0.debugMessages.append(message()) }
    }
}