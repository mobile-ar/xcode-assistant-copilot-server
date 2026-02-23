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

@Test func spyLoggerCapturesMessages() {
    let logger = MockLogger()
    logger.error("e1")
    logger.warn("w1")
    logger.info("i1")
    logger.debug("d1")

    #expect(logger.errorMessages == ["e1"])
    #expect(logger.warnMessages == ["w1"])
    #expect(logger.infoMessages == ["i1"])
    #expect(logger.debugMessages == ["d1"])
}

@Test func logLevelPriorityOrdering() {
    let levels: [LogLevel] = [.none, .error, .warning, .info, .debug, .all]
    for i in 0..<levels.count - 1 {
        #expect(levels[i].priority < levels[i + 1].priority)
    }
}
