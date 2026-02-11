import Foundation

public struct OAuthToken: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }

    public init(accessToken: String, tokenType: String = "bearer", scope: String = "") {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
    }
}

public struct DeviceCodeResponse: Codable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct DeviceCodePollResponse: Codable, Sendable {
    public let accessToken: String?
    public let tokenType: String?
    public let scope: String?
    public let error: String?
    public let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }

    public func toOAuthToken() -> OAuthToken? {
        guard let accessToken, let tokenType else { return nil }
        return OAuthToken(
            accessToken: accessToken,
            tokenType: tokenType,
            scope: scope ?? ""
        )
    }
}