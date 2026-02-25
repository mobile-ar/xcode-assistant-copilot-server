import Foundation

public struct DeviceCodeEndpoint: Endpoint {
    public let method: HTTPMethod = .post
    public let baseURL: String = "https://github.com"
    public let path: String = "/login/device/code"
    public let headers: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json"
    ]
    public let body: Data?

    public init(clientID: String, scope: String) {
        let dict: [String: String] = [
            "client_id": clientID,
            "scope": scope
        ]
        self.body = try? JSONSerialization.data(withJSONObject: dict)
    }
}