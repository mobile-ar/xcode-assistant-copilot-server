import Foundation
import Testing

@testable import XcodeAssistantCopilotServer

@Test func modelObjectInitSetsDefaultValues() {
    let model = ModelObject(id: "gpt-4o")
    #expect(model.id == "gpt-4o")
}

@Test func modelObjectEncodesWithSnakeCaseKeys() throws {
    let model = ModelObject(id: "gpt-4o")
    let data = try JSONEncoder().encode(model)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["id"] as? String == "gpt-4o")
}

@Test func modelObjectDecodesFromJSON() throws {
    let json = """
    { "id": "claude-sonnet-4" }
    """
    let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
    #expect(model.id == "claude-sonnet-4")
}

@Test func modelObjectRoundTrip() throws {
    let original = ModelObject(id: "gpt-4o")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ModelObject.self, from: data)

    #expect(decoded.id == original.id)
}

@Test func modelsResponseInitSetsObjectToList() {
    let response = ModelsResponse(data: [])
    #expect(response.data.isEmpty)
}

@Test func modelsResponseInitWithMultipleModels() {
    let models = [
        ModelObject(id: "gpt-4o"),
        ModelObject(id: "claude-sonnet-4"),
    ]
    let response = ModelsResponse(data: models)
    #expect(response.data.count == 2)
    #expect(response.data[0].id == "gpt-4o")
    #expect(response.data[1].id == "claude-sonnet-4")
}

@Test func modelsResponseEncodesCorrectly() throws {
    let models = [ModelObject(id: "gpt-4o")]
    let response = ModelsResponse(data: models)
    let data = try JSONEncoder().encode(response)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

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
    #expect(response.data.count == 2)
    #expect(response.data[0].id == "gpt-4o")
    #expect(response.data[1].id == "claude-sonnet-4")
}

@Test func modelsResponseRoundTrip() throws {
    let models = [
        ModelObject(id: "gpt-4o"),
        ModelObject(id: "claude-sonnet-4"),
    ]
    let original = ModelsResponse(data: models)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)

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
    #expect(response.data.isEmpty)
}
