import Darwin
import Dispatch
import Foundation

public protocol ConfigurationWatcherProtocol: Sendable {
    func start() async
    func stop() async
    func changes() async -> AsyncStream<ServerConfiguration>
}

public actor ConfigurationWatcher: ConfigurationWatcherProtocol {
    private let path: String
    private let loader: ConfigurationLoaderProtocol
    private let logger: LoggerProtocol
    private var continuation: AsyncStream<ServerConfiguration>.Continuation?
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var reopenTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var fileDescriptor: Int32 = -1

    private static let reopenAttempts = 5
    private static let reopenBaseDelayMilliseconds: Int = 50

    public init(path: String, loader: ConfigurationLoaderProtocol, logger: LoggerProtocol) {
        self.path = path
        self.loader = loader
        self.logger = logger
    }

    public func changes() -> AsyncStream<ServerConfiguration> {
        let stream = AsyncStream<ServerConfiguration> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.stop() }
            }
        }
        return stream
    }

    public func start() async {
        let fileDescriptor = Darwin.open(path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            logger.warn("ConfigurationWatcher: failed to open file at \(path)")
            return
        }
        self.fileDescriptor = fileDescriptor
        beginWatching(fileDescriptor: fileDescriptor)
    }

    public func stop() async {
        debounceTask?.cancel()
        debounceTask = nil
        reopenTask?.cancel()
        reopenTask = nil
        watchTask?.cancel()
        watchTask = nil
        source?.cancel()
        source = nil
        continuation?.finish()
        continuation = nil
        if fileDescriptor != -1 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func makeFileSystemEventStream(
        fileDescriptor: Int32
    ) -> (stream: AsyncStream<DispatchSource.FileSystemEvent>, source: DispatchSourceFileSystemObject) {
        let (stream, continuation) = AsyncStream<DispatchSource.FileSystemEvent>.makeStream()

        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .global()
        )

        // data must be captured synchronously inside the event handler while still on the GCD
        // queue — it is reset after the handler returns and is not safe to read later from an
        // async context. AsyncStream.Continuation is Sendable; yielding from a GCD queue is
        // safe under Swift 6 strict concurrency. This is the sole GCD-to-Swift-concurrency
        // bridge point: no Task trampoline is needed here.
        dispatchSource.setEventHandler {
            let rawValue = dispatchSource.data.rawValue
            continuation.yield(DispatchSource.FileSystemEvent(rawValue: rawValue))
        }

        dispatchSource.setCancelHandler {
            continuation.finish()
        }

        dispatchSource.resume()
        return (stream, dispatchSource)
    }

    private func beginWatching(fileDescriptor: Int32) {
        let (eventStream, dispatchSource) = makeFileSystemEventStream(fileDescriptor: fileDescriptor)
        source = dispatchSource
        watchTask?.cancel()
        watchTask = Task {
            defer { closeCancelledFileDescriptor(fileDescriptor) }
            for await event in eventStream {
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ eventData: DispatchSource.FileSystemEvent) {
        if eventData.contains(.delete) || eventData.contains(.rename) {
            source?.cancel()
            source = nil
            scheduleReopen()
        } else if eventData.contains(.write) {
            scheduleDebounce()
        }
    }

    private func scheduleReopen() {
        reopenTask?.cancel()
        reopenTask = Task {
            await reopenWithBackoff()
        }
    }

    private func reopenWithBackoff() async {
        for attempt in 0..<Self.reopenAttempts {
            let delayMs = Self.reopenBaseDelayMilliseconds * (1 << attempt)
            do {
                try await Task.sleep(for: .milliseconds(delayMs))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let fileDescriptor = Darwin.open(path, O_EVTONLY)
            if fileDescriptor != -1 {
                self.fileDescriptor = fileDescriptor
                beginWatching(fileDescriptor: fileDescriptor)
                scheduleDebounce()
                return
            }

            logger.warn("ConfigurationWatcher: failed to open file at \(path) (attempt \(attempt + 1)/\(Self.reopenAttempts))")
        }

        logger.warn("ConfigurationWatcher: giving up watching \(path) after \(Self.reopenAttempts) attempts")
    }

    private func closeCancelledFileDescriptor(_ fileDescriptor: Int32) {
        if self.fileDescriptor == fileDescriptor {
            Darwin.close(fileDescriptor)
            self.fileDescriptor = -1
        }
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                await triggerReload()
            } catch {
                // Task was cancelled — no action needed
            }
        }
    }

    private func triggerReload() async {
        do {
            let config = try loader.load(from: path)
            continuation?.yield(config)
        } catch {
            logger.warn("Failed to reload configuration: \(error)")
        }
    }
}
