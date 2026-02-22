import Foundation

extension FileHandle {
    func asyncDataStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { @Sendable _ in
                self.readabilityHandler = nil
            }
        }
    }
}