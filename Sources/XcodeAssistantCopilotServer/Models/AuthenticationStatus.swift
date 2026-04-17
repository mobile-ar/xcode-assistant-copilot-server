import Foundation

public enum AuthenticationState: String, Encodable, Sendable {
    case authenticated = "authenticated"
    case tokenExpired = "token_expired"
    case notConnected = "not_connected"
}

public struct AuthenticationStatus: Encodable, Sendable {
    public let state: AuthenticationState
    public let copilotTokenExpiry: String?

    public init(state: AuthenticationState, copilotTokenExpiry: String?) {
        self.state = state
        self.copilotTokenExpiry = copilotTokenExpiry
    }

    enum CodingKeys: String, CodingKey {
        case state
        case copilotTokenExpiry = "copilot_token_expiry"
    }
}