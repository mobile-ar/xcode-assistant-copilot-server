import Testing
@testable import XcodeAssistantCopilotServer

@Test func logLevelPriorities() {
    #expect(LogLevel.none.priority == 0)
    #expect(LogLevel.error.priority == 1)
    #expect(LogLevel.warning.priority == 2)
    #expect(LogLevel.info.priority == 3)
    #expect(LogLevel.debug.priority == 4)
    #expect(LogLevel.all.priority == 5)
}

@Test func logLevelRawValues() {
    #expect(LogLevel(rawValue: "none") == LogLevel.none)
    #expect(LogLevel(rawValue: "error") == .error)
    #expect(LogLevel(rawValue: "warning") == .warning)
    #expect(LogLevel(rawValue: "info") == .info)
    #expect(LogLevel(rawValue: "debug") == .debug)
    #expect(LogLevel(rawValue: "all") == .all)
    #expect(LogLevel(rawValue: "invalid") == nil)
}

@Test func logLevelAllCasesContainsAllLevels() {
    #expect(LogLevel.allCases.count == 6)
    #expect(LogLevel.allCases.contains(LogLevel.none))
    #expect(LogLevel.allCases.contains(.error))
    #expect(LogLevel.allCases.contains(.warning))
    #expect(LogLevel.allCases.contains(.info))
    #expect(LogLevel.allCases.contains(.debug))
    #expect(LogLevel.allCases.contains(.all))
}

@Test func loggerInitializesWithDefaultLevel() {
    let logger = Logger()
    #expect(logger.level == .info)
}

@Test func loggerInitializesWithSpecifiedLevel() {
    let logger = Logger(level: .debug)
    #expect(logger.level == .debug)
}

@Test func loggerConformsToLoggerProtocol() {
    let logger = Logger(level: .all)
    let protocolLogger: any LoggerProtocol = logger
    #expect(protocolLogger.level == .all)
}

@Test func loggerDoesNotCrashWhenLoggingAtAllLevels() {
    let logger = Logger(level: .all)
    logger.error("test error")
    logger.warn("test warning")
    logger.info("test info")
    logger.debug("test debug")
}

@Test func loggerWithNoneLevelDoesNotCrash() {
    let logger = Logger(level: .none)
    logger.error("should be suppressed")
    logger.warn("should be suppressed")
    logger.info("should be suppressed")
    logger.debug("should be suppressed")
}

final class SpyLogger: LoggerProtocol, @unchecked Sendable {
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

@Test func spyLoggerCapturesMessages() {
    let spy = SpyLogger()
    spy.error("e1")
    spy.warn("w1")
    spy.info("i1")
    spy.debug("d1")

    #expect(spy.errorMessages == ["e1"])
    #expect(spy.warnMessages == ["w1"])
    #expect(spy.infoMessages == ["i1"])
    #expect(spy.debugMessages == ["d1"])
}

@Test func logLevelPriorityOrdering() {
    let levels: [LogLevel] = [.none, .error, .warning, .info, .debug, .all]
    for i in 0..<levels.count - 1 {
        #expect(levels[i].priority < levels[i + 1].priority)
    }
}