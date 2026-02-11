import Foundation

public struct CopilotToken: Sendable {
    public let token: String
    public let expiresAt: Date
    public let apiEndpoint: String

    public init(token: String, expiresAt: Date, apiEndpoint: String = "https://api.individual.githubcopilot.com") {
        self.token = token
        self.expiresAt = expiresAt
        self.apiEndpoint = apiEndpoint
    }

    public var isExpired: Bool {
        Date.now >= expiresAt
    }

    public var isExpiringSoon: Bool {
        Date.now >= expiresAt.addingTimeInterval(-300)
    }

    public var isValid: Bool {
        !isExpired && !isExpiringSoon
    }
}

struct CopilotTokenEndpoints: Decodable, Sendable {
    let api: String?

    enum CodingKeys: String, CodingKey {
        case api
    }
}

struct CopilotTokenResponse: Decodable, Sendable {
    let token: String
    let expiresAt: Int
    let endpoints: CopilotTokenEndpoints?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case endpoints
    }

    private static let defaultAPIEndpoint = "https://api.individual.githubcopilot.com"

    func toCopilotToken() -> CopilotToken {
        let apiEndpoint = endpoints?.api ?? Self.defaultAPIEndpoint
        return CopilotToken(
            token: token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt)),
            apiEndpoint: apiEndpoint
        )
    }
}