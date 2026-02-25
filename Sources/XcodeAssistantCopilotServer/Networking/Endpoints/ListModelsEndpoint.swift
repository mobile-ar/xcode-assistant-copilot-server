import Foundation

public struct ListModelsEndpoint: Endpoint {
    public let method: HTTPMethod = .get
    public let baseURL: String
    public let path = "/models"
    public let headers: [String: String]

    public init(credentials: CopilotCredentials) {
        self.baseURL = credentials.apiEndpoint
        self.headers = CopilotRequestHeaders.standard(token: credentials.token)
    }
}