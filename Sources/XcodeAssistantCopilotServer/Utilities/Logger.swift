import Foundation
import Logging
import Synchronization

public enum LogLevel: String, Sendable, CaseIterable {
    case none
    case error
    case warning
    case info
    case debug
    case all

    var priority: Int {
        switch self {
        case .none: 0
        case .error: 1
        case .warning: 2
        case .info: 3
        case .debug: 4
        case .all: 5
        }
    }

    var loggingLevel: Logging.Logger.Level {
        switch self {
        case .none: .critical
        case .error: .error
        case .warning: .warning
        case .info: .info
        case .debug: .debug
        case .all: .trace
        }
    }
}

public protocol LoggerProtocol: Sendable {
    var level: LogLevel { get }
    func error(_ message: @autoclosure () -> String)
    func warn(_ message: @autoclosure () -> String)
    func info(_ message: @autoclosure () -> String)
    func debug(_ message: @autoclosure () -> String)
}

public final class AppLogger: LoggerProtocol, Sendable {
    public let level: LogLevel
    private let logger: Logging.Logger

    public init(level: LogLevel = .info, label: String = "copilot-server") {
        self.level = level
        var logger = Logging.Logger(label: label)
        logger.logLevel = level.loggingLevel
        self.logger = logger
    }

    private static let isBootstrapped = Atomic<Bool>(false)

    public static func bootstrap() {
        guard isBootstrapped.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged else {
            return
        }
        LoggingSystem.bootstrap { label in
            TimestampedLogHandler(label: label)
        }
    }

    public func error(_ message: @autoclosure () -> String) {
        guard level.priority >= LogLevel.error.priority else { return }
        logger.error("\(message())")
    }

    public func warn(_ message: @autoclosure () -> String) {
        guard level.priority >= LogLevel.warning.priority else { return }
        logger.warning("\(message())")
    }

    public func info(_ message: @autoclosure () -> String) {
        guard level.priority >= LogLevel.info.priority else { return }
        logger.info("\(message())")
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard level.priority >= LogLevel.debug.priority else { return }
        logger.debug("\(message())")
    }
}

struct TimestampedLogHandler: LogHandler {
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info
    private let label: String

    init(label: String) {
        self.label = label
    }

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let timestamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        let levelString = levelPrefix(event.level)
        let output = "[\(timestamp)] [\(levelString)] \(event.message)"
        var stderr = FileHandle.standardError
        Swift.print(output, to: &stderr)
    }

    private func levelPrefix(_ level: Logging.Logger.Level) -> String {
        switch level {
        case .trace: "TRACE"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .warning: "WARN"
        case .error: "ERROR"
        case .critical: "CRITICAL"
        }
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
