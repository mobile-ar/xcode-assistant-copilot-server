import Foundation
import Synchronization

private let signalWriteFD = Atomic<CInt>(-1)

private func signalCallback(_ sig: CInt) {
    var byte = UInt8(truncatingIfNeeded: sig)
    let fd = signalWriteFD.load(ordering: .acquiring)
    _ = Darwin.write(fd, &byte, 1)
}

public protocol SignalHandlerProtocol: Sendable {
    func monitorSignals(_ handler: @escaping @Sendable (Int32) async -> Void)
}

public final class SignalHandler: SignalHandlerProtocol, Sendable {
    private let signals: [Int32]
    private let logger: LoggerProtocol
    private let readFileDescriptor: CInt
    private let writeFileDescriptor: CInt
    private let monitoringTask: Mutex<Task<Void, Never>?>

    public init(signals: [Int32] = [SIGTERM, SIGINT], logger: LoggerProtocol) {
        self.signals = signals
        self.logger = logger
        self.monitoringTask = Mutex(nil)

        var fds: [CInt] = [0, 0]
        let result = pipe(&fds)
        precondition(result == 0, "Failed to create signal pipe")
        self.readFileDescriptor = fds[0]
        self.writeFileDescriptor = fds[1]

        let flags = fcntl(fds[1], F_GETFL)
        _ = fcntl(fds[1], F_SETFL, flags | O_NONBLOCK)

        signalWriteFD.store(writeFileDescriptor, ordering: .releasing)
    }

    deinit {
        monitoringTask.withLock { task in
            task?.cancel()
            task = nil
        }
        close(readFileDescriptor)
        close(writeFileDescriptor)
    }

    public func monitorSignals(_ handler: @escaping @Sendable (Int32) async -> Void) {
        for sig in signals {
            signal(sig, signalCallback)
            logger.debug("Installed signal handler for signal \(sig)")
        }

        let readFD = readFileDescriptor
        let logger = logger

        let task = Task.detached { [logger] in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            defer { buffer.deallocate() }

            while !Task.isCancelled {
                let bytesRead = Darwin.read(readFD, buffer, 1)
                if Task.isCancelled { return }

                if bytesRead > 0 {
                    let sig = Int32(buffer.pointee)
                    logger.info("Received signal \(sig), initiating graceful shutdown...")
                    await handler(sig)
                    return
                } else if bytesRead == 0 {
                    return
                } else {
                    let err = errno
                    if err == EINTR { continue }
                    if err == EBADF { return }
                    return
                }
            }
        }

        monitoringTask.withLock { $0 = task }
    }
}