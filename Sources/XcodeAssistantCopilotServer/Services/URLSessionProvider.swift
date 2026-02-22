import Foundation

public struct URLSessionProvider {

    public static func configuredSession(
        timeoutIntervalForRequest: TimeInterval = 300,
        waitsForConnectivity: Bool = true,
        httpMaximumConnectionsPerHost: Int = 6
    ) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.waitsForConnectivity = waitsForConnectivity
        configuration.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        return URLSession(configuration: configuration)
    }

}
