import Foundation

public struct SSEEvent: Sendable {
    private static let jsonDecoder = JSONDecoder()

    public let data: String
    public let event: String?
    public let id: String?

    public init(data: String, event: String? = nil, id: String? = nil) {
        self.data = data
        self.event = event
        self.id = id
    }

    public var isDone: Bool {
        data == "[DONE]"
    }

    public func decodeData<T: Decodable>(_ type: T.Type) throws -> T {
        guard let jsonData = data.data(using: .utf8) else {
            throw SSEParserError.invalidData("Failed to convert SSE data to UTF-8")
        }
        return try SSEEvent.jsonDecoder.decode(type, from: jsonData)
    }
}

public enum SSEParserError: Error, CustomStringConvertible {
    case invalidData(String)
    case streamInterrupted

    public var description: String {
        switch self {
        case .invalidData(let message):
            "Invalid SSE data: \(message)"
        case .streamInterrupted:
            "SSE stream was interrupted"
        }
    }
}

public struct SSEParser: Sendable {
    public init() {}

    public func parseLines(_ lines: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<SSEEvent, Error> {
        parseLineSequence(lines)
    }

    private func parseLineSequence<S: AsyncSequence & Sendable>(_ lines: S) -> AsyncThrowingStream<SSEEvent, Error> where S.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                var currentEvent: String?
                var currentId: String?

                do {
                    for try await line in lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if line.isEmpty {
                            continue
                        }

                        if line.hasPrefix("data:") {
                            let value = extractFieldValue(from: line, prefix: "data:")
                            guard !value.isEmpty else { continue }
                            let event = SSEEvent(
                                data: value,
                                event: currentEvent,
                                id: currentId
                            )
                            continuation.yield(event)
                        } else if line.hasPrefix("event:") {
                            currentEvent = extractFieldValue(from: line, prefix: "event:")
                        } else if line.hasPrefix("id:") {
                            currentId = extractFieldValue(from: line, prefix: "id:")
                        } else if line.hasPrefix(":") {
                            continue
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func extractFieldValue(from line: String, prefix: String) -> String {
        var value = String(line.dropFirst(prefix.count))
        if value.hasPrefix(" ") {
            value = String(value.dropFirst())
        }
        return value
    }
}
