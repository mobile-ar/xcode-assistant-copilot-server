import Foundation

public struct AccessTokenPollEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String = "https://github.com"
    public let path: String = "/login/oauth/access_token"
    public let headers: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json"
    ]
    public let body: Data?

    public init(clientID: String, deviceCode: String) {
        let dict: [String: String] = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        self.body = try? JSONSerialization.data(withJSONObject: dict)
    }
}