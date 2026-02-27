import Foundation
import Testing

@testable import XcodeAssistantCopilotServer

@Test func modelObjectInitSetsDefaultValues() {
    let model = ModelObject(id: "gpt-4o")
    #expect(model.id == "gpt-4o")
    #expect(model.object == "model")
    #expect(model.ownedBy == "github-copilot")
    #expect(model.created > 0)
}

@Test func modelObjectInitWithCustomValues() {
    let model = ModelObject(id: "custom-model", created: 1700000000, ownedBy: "custom-owner")
    #expect(model.id == "custom-model")
    #expect(model.object == "model")
    #expect(model.created == 1700000000)
    #expect(model.ownedBy == "custom-owner")
}

@Test func modelObjectEncodesWithSnakeCaseKeys() throws {
    let model = ModelObject(id: "gpt-4o", created: 1700000000, ownedBy: "github-copilot")
    let data = try JSONEncoder().encode(model)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["id"] as? String == "gpt-4o")
    #expect(json?["object"] as? String == "model")
    #expect(json?["created"] as? Int == 1700000000)
    #expect(json?["owned_by"] as? String == "github-copilot")
    #expect(json?["ownedBy"] == nil)
}

@Test func modelObjectDecodesFromJSON() throws {
    let json = """
    {
        "id": "claude-sonnet-4",
        "object": "model",
        "created": 1700000000,
        "owned_by": "anthropic"
    }
    """
    let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
    #expect(model.id == "claude-sonnet-4")
    #expect(model.object == "model")
    #expect(model.created == 1700000000)
    #expect(model.ownedBy == "anthropic")
}

@Test func modelObjectRoundTrip() throws {
    let original = ModelObject(id: "gpt-4o", created: 1700000000, ownedBy: "github-copilot")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ModelObject.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.object == original.object)
    #expect(decoded.created == original.created)
    #expect(decoded.ownedBy == original.ownedBy)
}

@Test func modelsResponseInitSetsObjectToList() {
    let response = ModelsResponse(data: [])
    #expect(response.object == "list")
    #expect(response.data.isEmpty)
}

@Test func modelsResponseInitWithMultipleModels() {
    let models = [
        ModelObject(id: "gpt-4o", created: 1700000000),
        ModelObject(id: "claude-sonnet-4", created: 1700000001),
    ]
    let response = ModelsResponse(data: models)
    #expect(response.object == "list")
    #expect(response.data.count == 2)
    #expect(response.data[0].id == "gpt-4o")
    #expect(response.data[1].id == "claude-sonnet-4")
}

@Test func modelsResponseEncodesCorrectly() throws {
    let models = [ModelObject(id: "gpt-4o", created: 1700000000)]
    let response = ModelsResponse(data: models)
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["object"] as? String == "list")
    let dataArray = json?["data"] as? [[String: Any]]
    #expect(dataArray?.count == 1)
    #expect(dataArray?[0]["id"] as? String == "gpt-4o")
}

@Test func modelsResponseDecodesFromJSON() throws {
    let json = """
    {
        "object": "list",
        "data": [
            {
                "id": "gpt-4o",
                "object": "model",
                "created": 1700000000,
                "owned_by": "github-copilot"
            },
            {
                "id": "claude-sonnet-4",
                "object": "model",
                "created": 1700000001,
                "owned_by": "anthropic"
            }
        ]
    }
    """
    let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
    #expect(response.object == "list")
    #expect(response.data.count == 2)
    #expect(response.data[0].id == "gpt-4o")
    #expect(response.data[0].ownedBy == "github-copilot")
    #expect(response.data[1].id == "claude-sonnet-4")
    #expect(response.data[1].ownedBy == "anthropic")
}

@Test func modelsResponseRoundTrip() throws {
    let models = [
        ModelObject(id: "gpt-4o", created: 1700000000),
        ModelObject(id: "claude-sonnet-4", created: 1700000001, ownedBy: "anthropic"),
    ]
    let original = ModelsResponse(data: models)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)

    #expect(decoded.object == original.object)
    #expect(decoded.data.count == original.data.count)
    #expect(decoded.data[0].id == original.data[0].id)
    #expect(decoded.data[1].id == original.data[1].id)
}

@Test func modelsResponseDecodesWithEmptyDataArray() throws {
    let json = """
    {
        "object": "list",
        "data": []
    }
    """
    let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
    #expect(response.object == "list")
    #expect(response.data.isEmpty)
}

@Test func modelObjectDefaultCreatedTimestampIsRecent() {
    let before = Int(Date.now.timeIntervalSince1970)
    let model = ModelObject(id: "test")
    let after = Int(Date.now.timeIntervalSince1970)
    #expect(model.created >= before)
    #expect(model.created <= after)
}