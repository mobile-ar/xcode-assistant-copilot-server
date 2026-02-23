import Foundation

public struct SSEEvent: Sendable {
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
        return try JSONDecoder().decode(type, from: jsonData)
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

    public func parse(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        parseLineSequence(bytes.lines)
    }

    public func parseLines(_ lines: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<SSEEvent, Error> {
        parseLineSequence(lines)
    }

    private func parseLineSequence<S: AsyncSequence & Sendable>(_ lines: S) -> AsyncThrowingStream<SSEEvent, Error> where S.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                var currentEvent: String?
                var currentId: String?
                var dataLines: [String] = []

                do {
                    for try await line in lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let data = dataLines.joined(separator: "\n")
                                let event = SSEEvent(
                                    data: data,
                                    event: currentEvent,
                                    id: currentId
                                )
                                continuation.yield(event)
                                dataLines.removeAll()
                                currentEvent = nil
                                currentId = nil
                            }
                            continue
                        }

                        if line.hasPrefix("data:") {
                            let value = extractFieldValue(from: line, prefix: "data:")
                            dataLines.append(value)
                        } else if line.hasPrefix("event:") {
                            if !dataLines.isEmpty {
                                let data = dataLines.joined(separator: "\n")
                                let event = SSEEvent(data: data, event: currentEvent,id: currentId)
                                continuation.yield(event)
                                dataLines.removeAll()
                                currentId = nil
                            }
                            currentEvent = extractFieldValue(from: line, prefix: "event:")
                        } else if line.hasPrefix("id:") {
                            if !dataLines.isEmpty {
                                let data = dataLines.joined(separator: "\n")
                                let event = SSEEvent(data: data, event: currentEvent, id: currentId)
                                continuation.yield(event)
                                dataLines.removeAll()
                                currentEvent = nil
                                currentId = nil
                            }
                            currentId = extractFieldValue(from: line, prefix: "id:")
                        } else if line.hasPrefix(":") {
                            continue
                        }
                    }

                    if !dataLines.isEmpty {
                        let data = dataLines.joined(separator: "\n")
                        let event = SSEEvent(data: data, event: currentEvent, id: currentId)
                        continuation.yield(event)
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

    public func parseLine(_ line: String) -> SSEEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let value = extractFieldValue(from: line, prefix: "data:")
        guard !value.isEmpty else { return nil }
        return SSEEvent(data: value)
    }

    private func extractFieldValue(from line: String, prefix: String) -> String {
        var value = String(line.dropFirst(prefix.count))
        if value.hasPrefix(" ") {
            value = String(value.dropFirst())
        }
        return value
    }
}
