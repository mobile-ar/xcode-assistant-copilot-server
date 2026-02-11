import Foundation

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
}

public protocol LoggerProtocol: Sendable {
    var level: LogLevel { get }
    func error(_ message: String)
    func warn(_ message: String)
    func info(_ message: String)
    func debug(_ message: String)
}

public final class Logger: LoggerProtocol, @unchecked Sendable {
    public let level: LogLevel
    private let threshold: Int
    private let lock = NSLock()

    public init(level: LogLevel = .info) {
        self.level = level
        self.threshold = level.priority
    }

    public func error(_ message: String) {
        log(message, at: .error, prefix: "ERROR")
    }

    public func warn(_ message: String) {
        log(message, at: .warning, prefix: "WARN")
    }

    public func info(_ message: String) {
        log(message, at: .info, prefix: "INFO")
    }

    public func debug(_ message: String) {
        log(message, at: .debug, prefix: "DEBUG")
    }

    private func log(_ message: String, at level: LogLevel, prefix: String) {
        guard threshold >= level.priority else { return }
        lock.lock()
        defer { lock.unlock() }
        print("[\(prefix)] \(message)")
    }
}