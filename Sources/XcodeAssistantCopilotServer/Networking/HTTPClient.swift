import Foundation

public protocol HTTPClientProtocol: Sendable {
    func execute(_ endpoint: any Endpoint) async throws -> DataResponse
    func stream(_ endpoint: any Endpoint) async throws -> StreamResponse
}

public struct HTTPClient: HTTPClientProtocol {
    private let session: URLSession

    public init(
        timeoutIntervalForRequest: TimeInterval = 300,
        waitsForConnectivity: Bool = true,
        httpMaximumConnectionsPerHost: Int = 6
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.waitsForConnectivity = waitsForConnectivity
        configuration.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        self.session = URLSession(configuration: configuration)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func execute(_ endpoint: any Endpoint) async throws -> DataResponse {
        let request = try endpoint.buildURLRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPClientError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        return DataResponse(data: data, statusCode: httpResponse.statusCode)
    }

    public func stream(_ endpoint: any Endpoint) async throws -> StreamResponse {
        let request = try endpoint.buildURLRequest()

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw HTTPClientError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let statusCode = httpResponse.statusCode

        guard (200...299).contains(statusCode) else {
            var collectedData = Data()
            for try await byte in bytes {
                collectedData.append(byte)
            }
            let body = String(data: collectedData, encoding: .utf8) ?? ""
            return StreamResponse(statusCode: statusCode, content: .errorBody(body))
        }

        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(line)
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

        return StreamResponse(statusCode: statusCode, content: .lines(lines))
    }
}