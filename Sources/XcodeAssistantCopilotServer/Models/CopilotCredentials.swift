public struct CopilotCredentials: Sendable {
    public let token: String
    public let apiEndpoint: String

    public init(token: String, apiEndpoint: String) {
        self.token = token
        self.apiEndpoint = apiEndpoint
    }
}