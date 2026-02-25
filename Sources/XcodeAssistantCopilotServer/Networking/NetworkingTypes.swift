import Foundation

public struct DataResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public struct StreamResponse: Sendable {
    public let statusCode: Int
    public let content: StreamContent

    public init(statusCode: Int, content: StreamContent) {
        self.statusCode = statusCode
        self.content = content
    }
}

public enum StreamContent: Sendable {
    case lines(AsyncThrowingStream<String, Error>)
    case errorBody(String)
}

public enum HTTPClientError: Error, CustomStringConvertible {
    case invalidURL(String)
    case invalidResponse
    case networkError(String)

    public var description: String {
        switch self {
        case .invalidURL(let url):
            "Invalid URL: \(url)"
        case .invalidResponse:
            "Received an invalid (non-HTTP) response"
        case .networkError(let message):
            "Network error: \(message)"
        }
    }
}