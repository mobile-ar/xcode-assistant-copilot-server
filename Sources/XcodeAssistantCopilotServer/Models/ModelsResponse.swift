import Foundation

public struct ModelObject: Codable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }

    public init(id: String, created: Int = ChatCompletionChunk.currentTimestamp(), ownedBy: String = "github-copilot") {
        self.id = id
        self.object = "model"
        self.created = created
        self.ownedBy = ownedBy
    }
}

public struct ModelsResponse: Codable, Sendable {
    public let object: String
    public let data: [ModelObject]

    public init(data: [ModelObject]) {
        self.object = "list"
        self.data = data
    }
}