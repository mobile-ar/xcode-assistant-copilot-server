import Foundation
import Testing

@testable import XcodeAssistantCopilotServer

@Test func copilotModelsResponseDecodesDataArray() throws {
    let json = """
    {"data": [{"id": "gpt-4o"}, {"id": "claude-sonnet-4"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 2)
    #expect(response.allModels[0].id == "gpt-4o")
    #expect(response.allModels[1].id == "claude-sonnet-4")
}

@Test func copilotModelsResponseDecodesModelsArray() throws {
    let json = """
    {"models": [{"id": "gpt-4o"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "gpt-4o")
}

@Test func copilotModelsResponsePrefersDataOverModels() throws {
    let json = """
    {"data": [{"id": "from-data"}], "models": [{"id": "from-models"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "from-data")
}

@Test func copilotModelsResponseReturnsEmptyWhenBothMissing() throws {
    let json = """
    {}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelsResponseSkipsModelsWithMissingId() throws {
    let json = """
    {"data": [{"id": "valid-model"}, {"name": "no-id-model"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "valid-model")
}

@Test func copilotModelsResponseSkipsMalformedModels() throws {
    let json = """
    {"data": [{"id": "good"}, "not-an-object", {"id": "also-good"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 2)
    #expect(response.allModels[0].id == "good")
    #expect(response.allModels[1].id == "also-good")
}

@Test func copilotModelDecodesAllFields() throws {
    let json = """
    {
        "id": "gpt-4o",
        "name": "GPT-4o",
        "version": "2024-05-13",
        "capabilities": {
            "family": "gpt-4o",
            "type": "chat",
            "supports": {
                "reasoning_effort": false,
                "streaming": true,
                "tool_calls": true,
                "parallel_tool_calls": true,
                "structured_outputs": false,
                "vision": true
            }
        },
        "supported_endpoints": ["/chat/completions", "/responses"]
    }
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-4o")
    #expect(model.name == "GPT-4o")
    #expect(model.version == "2024-05-13")
    #expect(model.capabilities?.family == "gpt-4o")
    #expect(model.capabilities?.type == "chat")
    #expect(model.capabilities?.supports?.reasoningEffort == false)
    #expect(model.capabilities?.supports?.streaming == true)
    #expect(model.capabilities?.supports?.toolCalls == true)
    #expect(model.capabilities?.supports?.parallelToolCalls == true)
    #expect(model.capabilities?.supports?.structuredOutputs == false)
    #expect(model.capabilities?.supports?.vision == true)
    #expect(model.supportedEndpoints == ["/chat/completions", "/responses"])
}

@Test func copilotModelDecodesWithOnlyId() throws {
    let json = """
    {"id": "gpt-4o"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-4o")
    #expect(model.name == nil)
    #expect(model.version == nil)
    #expect(model.capabilities == nil)
    #expect(model.supportedEndpoints == nil)
}

@Test func copilotModelGracefullyHandlesUnexpectedCapabilitiesType() throws {
    let json = """
    {"id": "test-model", "capabilities": "unexpected-string"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "test-model")
    #expect(model.capabilities == nil)
}

@Test func copilotModelGracefullyHandlesUnexpectedSupportedEndpointsType() throws {
    let json = """
    {"id": "test-model", "supported_endpoints": "not-an-array"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "test-model")
    #expect(model.supportedEndpoints == nil)
}

@Test func copilotModelCapabilitiesGracefullyHandlesUnexpectedSupportsType() throws {
    let json = """
    {"family": "gpt-4o", "type": "chat", "supports": "unexpected"}
    """
    let capabilities = try JSONDecoder().decode(CopilotModelCapabilities.self, from: Data(json.utf8))
    #expect(capabilities.family == "gpt-4o")
    #expect(capabilities.type == "chat")
    #expect(capabilities.supports == nil)
}

@Test func copilotModelSupportsDecodesBooleanValues() throws {
    let json = """
    {"streaming": true, "tool_calls": false, "vision": true}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == false)
    #expect(supports.vision == true)
    #expect(supports.reasoningEffort == nil)
    #expect(supports.parallelToolCalls == nil)
    #expect(supports.structuredOutputs == nil)
}

@Test func copilotModelSupportsDecodesIntegerAsBool() throws {
    let json = """
    {"streaming": 1, "tool_calls": 0, "vision": 1}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == false)
    #expect(supports.vision == true)
}

@Test func copilotModelSupportsDecodesStringAsBool() throws {
    let json = """
    {"streaming": "true", "tool_calls": "false", "vision": "yes", "reasoning_effort": "no"}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == false)
    #expect(supports.vision == true)
    #expect(supports.reasoningEffort == false)
}

@Test func copilotModelSupportsDecodesStringOneAndZeroAsBool() throws {
    let json = """
    {"streaming": "1", "tool_calls": "0"}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == false)
}

@Test func copilotModelSupportsReturnsNilForUnrecognizedStringValue() throws {
    let json = """
    {"streaming": "maybe", "tool_calls": "sometimes"}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == nil)
    #expect(supports.toolCalls == nil)
}

@Test func copilotModelSupportsHandlesEmptyObject() throws {
    let json = """
    {}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == nil)
    #expect(supports.toolCalls == nil)
    #expect(supports.parallelToolCalls == nil)
    #expect(supports.structuredOutputs == nil)
    #expect(supports.vision == nil)
    #expect(supports.reasoningEffort == nil)
}

@Test func copilotModelSupportsIgnoresUnknownKeys() throws {
    let json = """
    {"streaming": true, "new_unknown_field": "something", "another_field": 42}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
}

@Test func copilotModelsResponseHandlesEmptyDataArray() throws {
    let json = """
    {"data": []}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelsResponseDecodesRealWorldPayload() throws {
    let json = """
    {
        "data": [
            {
                "id": "gpt-4o",
                "name": "GPT-4o",
                "version": "2024-05-13",
                "capabilities": {
                    "family": "gpt-4o",
                    "type": "chat",
                    "supports": {
                        "streaming": true,
                        "tool_calls": true,
                        "parallel_tool_calls": true,
                        "structured_outputs": true,
                        "vision": true
                    }
                },
                "supported_endpoints": ["/chat/completions"]
            },
            {
                "id": "gpt-5.1-codex",
                "name": "GPT-5.1 Codex",
                "version": "2025-01-01",
                "capabilities": {
                    "family": "gpt-5.1",
                    "type": "chat",
                    "supports": {
                        "reasoning_effort": true,
                        "streaming": true,
                        "tool_calls": true
                    }
                },
                "supported_endpoints": ["/responses"]
            }
        ]
    }
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 2)

    let gpt4o = response.allModels[0]
    #expect(gpt4o.id == "gpt-4o")
    #expect(gpt4o.supportsChatCompletions == true)
    #expect(gpt4o.requiresResponsesAPI == false)

    let codex = response.allModels[1]
    #expect(codex.id == "gpt-5.1-codex")
    #expect(codex.requiresResponsesAPI == true)
    #expect(codex.supportsChatCompletions == false)
}

@Test func copilotModelsResponseHandlesNullDataField() throws {
    let json = """
    {"data": null}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelCapabilitiesDecodesWithAllFieldsNil() throws {
    let json = """
    {}
    """
    let capabilities = try JSONDecoder().decode(CopilotModelCapabilities.self, from: Data(json.utf8))
    #expect(capabilities.family == nil)
    #expect(capabilities.type == nil)
    #expect(capabilities.supports == nil)
}

@Test func copilotModelSupportsDecodesStringCaseInsensitive() throws {
    let json = """
    {"streaming": "TRUE", "tool_calls": "False", "vision": "YES"}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == false)
    #expect(supports.vision == true)
}

@Test func copilotModelsResponseInitWithDataParameter() {
    let models = [CopilotModel(id: "test")]
    let response = CopilotModelsResponse(data: models)
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "test")
}

@Test func copilotModelsResponseInitWithModelsParameter() {
    let models = [CopilotModel(id: "test")]
    let response = CopilotModelsResponse(models: models)
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "test")
}

@Test func copilotModelsResponseInitWithBothNilReturnsEmpty() {
    let response = CopilotModelsResponse()
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelSupportsDecodesNonZeroIntAsTrue() throws {
    let json = """
    {"streaming": 42, "tool_calls": -1}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == true)
}

@Test func copilotModelsResponseDecodesWithExtraTopLevelKeys() throws {
    let json = """
    {"data": [{"id": "gpt-4o"}], "object": "list", "total": 1}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
}

@Test func copilotModelDecodesWithExtraUnknownFields() throws {
    let json = """
    {"id": "gpt-4o", "object": "model", "created": 1715616000, "owned_by": "openai", "unknown_field": true}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.id == "gpt-4o")
}

@Test func copilotModelCapabilitiesDecodesWithExtraFields() throws {
    let json = """
    {"family": "gpt-4o", "type": "chat", "limits": {"max_tokens": 4096}, "extra": "value"}
    """
    let capabilities = try JSONDecoder().decode(CopilotModelCapabilities.self, from: Data(json.utf8))
    #expect(capabilities.family == "gpt-4o")
    #expect(capabilities.type == "chat")
    #expect(capabilities.supports == nil)
}

@Test func decodingErrorDetailTypeMismatch() {
    let json = """
    {"id": 123}
    """
    do {
        _ = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
        Issue.record("Expected decoding error")
    } catch let error as DecodingError {
        let detail = CopilotAPIService.decodingErrorDetail(error)
        #expect(detail.contains("id"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func decodingErrorDetailKeyNotFound() {
    struct RequiredKey: Decodable {
        let requiredField: String
    }
    let json = """
    {}
    """
    do {
        _ = try JSONDecoder().decode(RequiredKey.self, from: Data(json.utf8))
        Issue.record("Expected decoding error")
    } catch let error as DecodingError {
        let detail = CopilotAPIService.decodingErrorDetail(error)
        #expect(detail.contains("Key not found"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func decodingErrorDetailDataCorrupted() {
    let json = "not valid json at all"
    do {
        _ = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
        Issue.record("Expected decoding error")
    } catch let error as DecodingError {
        let detail = CopilotAPIService.decodingErrorDetail(error)
        #expect(detail.contains("Data corrupted"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func copilotModelsResponseSkipsNullEntriesInArray() throws {
    let json = """
    {"data": [{"id": "valid"}, null, {"id": "also-valid"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 2)
    #expect(response.allModels[0].id == "valid")
    #expect(response.allModels[1].id == "also-valid")
}

@Test func copilotModelSupportsMixedBoolAndStringValues() throws {
    let json = """
    {"streaming": true, "tool_calls": "true", "vision": 1, "reasoning_effort": "false"}
    """
    let supports = try JSONDecoder().decode(CopilotModelSupports.self, from: Data(json.utf8))
    #expect(supports.streaming == true)
    #expect(supports.toolCalls == true)
    #expect(supports.vision == true)
    #expect(supports.reasoningEffort == false)
}