import Foundation

public struct ModelObject: Codable, Sendable {
    public let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }
}

public struct ModelsResponse: Codable, Sendable {
    public let data: [ModelObject]
}
