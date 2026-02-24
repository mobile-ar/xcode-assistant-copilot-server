import Foundation
import Synchronization
import Testing

@testable import XcodeAssistantCopilotServer

@Suite("SignalHandler Tests", .serialized)
struct SignalHandlerTests {

    @Test("Initializes with default signals SIGTERM and SIGINT")
    func initializesWithDefaultSignals() {
        let logger = MockLogger()
        let handler = SignalHandler(logger: logger)

        _ = handler
    }

    @Test("Initializes with custom signals")
    func initializesWithCustomSignals() {
        let logger = MockLogger()
        let handler = SignalHandler(signals: [SIGUSR1], logger: logger)

        _ = handler
    }

    @Test("monitorSignals installs signal handlers and logs debug messages")
    func monitorSignalsInstallsHandlers() async throws {
        let logger = MockLogger()
        let handler = SignalHandler(signals: [SIGUSR1], logger: logger)

        handler.monitorSignals { _ in }

        try await Task.sleep(for: .milliseconds(50))

        #expect(logger.debugMessages.contains { $0.contains("Installed signal handler for signal") })

        _ = handler
    }

    @Test("monitorSignals invokes handler when signal is received")
    func monitorSignalsInvokesHandler() async throws {
        let logger = MockLogger()
        let handler = SignalHandler(signals: [SIGUSR1], logger: logger)

        let handlerCalled = Mutex(false)
        let receivedSignal = Mutex<Int32?>(nil)

        handler.monitorSignals { sig in
            handlerCalled.withLock { $0 = true }
            receivedSignal.withLock { $0 = sig }
        }

        try await Task.sleep(for: .milliseconds(50))

        kill(getpid(), SIGUSR1)

        try await Task.sleep(for: .milliseconds(200))

        let wasCalled = handlerCalled.withLock { $0 }
        let signalValue = receivedSignal.withLock { $0 }
        #expect(wasCalled)
        #expect(signalValue == SIGUSR1)
        #expect(logger.infoMessages.contains { $0.contains("graceful shutdown") })

        _ = handler
    }

    @Test("monitorSignals logs the signal number received")
    func logsSignalNumber() async throws {
        let logger = MockLogger()
        let handler = SignalHandler(signals: [SIGUSR2], logger: logger)

        handler.monitorSignals { _ in }

        try await Task.sleep(for: .milliseconds(50))

        kill(getpid(), SIGUSR2)

        try await Task.sleep(for: .milliseconds(200))

        let signalNumber = SIGUSR2
        #expect(logger.infoMessages.contains { $0.contains("Received signal \(signalNumber)") })

        _ = handler
    }
}