import Foundation

public protocol Endpoint: Sendable {
    var method: HTTPMethod { get }
    var baseURL: String { get }
    var path: String { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var timeoutInterval: TimeInterval { get }
}

extension Endpoint {

    public var body: Data? { nil }

    public var timeoutInterval: TimeInterval { 60 }

    public func buildURLRequest() throws -> URLRequest {
        let urlString = baseURL + path
        guard let url = URL(string: urlString) else {
            throw HTTPClientError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        return request
    }
}