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

@Test func copilotModelsResponsePrefersDataOverModels() throws {
    let json = """
    {"data": [{"id": "from-data"}], "models": [{"id": "from-models"}]}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
    #expect(response.allModels[0].id == "from-data")
}

@Test func copilotModelsResponseReturnsEmptyWhenBothMissing() throws {
    let json = "{}"
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

@Test func copilotModelsResponseHandlesNullDataField() throws {
    let json = """
    {"data": null}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelsResponseHandlesEmptyDataArray() throws {
    let json = """
    {"data": []}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.isEmpty)
}

@Test func copilotModelsResponseDecodesWithExtraTopLevelKeys() throws {
    let json = """
    {"data": [{"id": "gpt-4o"}], "object": "list", "total": 1}
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 1)
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

@Test func copilotModelsResponseDecodesRealWorldPayload() throws {
    let json = """
    {
        "data": [
            {
                "capabilities" : {
                    "family" : "gpt-4o",
                    "limits" : {
                        "max_context_window_tokens" : 128000,
                        "max_output_tokens" : 4096,
                        "max_prompt_tokens" : 64000,
                        "vision" : {
                            "max_prompt_image_size" : 3145728,
                            "max_prompt_images" : 1,
                            "supported_media_types" : [
                                "image/jpeg",
                                "image/png",
                                "image/webp",
                                "image/gif"
                                ]
                        }
                    },
                    "object" : "model_capabilities",
                    "supports" : {
                        "parallel_tool_calls" : true,
                        "streaming" : true,
                        "tool_calls" : true,
                        "vision" : true
                        },
                    "tokenizer" : "o200k_base",
                    "type" : "chat"
                },
                "id" : "gpt-4o-2024-05-13",
                "model_picker_enabled" : false,
                "name" : "GPT-4o",
                "object" : "model",
                "preview" : false,
                "vendor" : "Azure OpenAI",
                "version" : "gpt-4o-2024-05-13"
            },
            {
                "capabilities" : {
                    "family" : "gpt-5.1-codex",
                    "limits" : {
                        "max_context_window_tokens" : 400000,
                        "max_output_tokens" : 128000,
                        "max_prompt_tokens" : 128000,
                        "vision" : {
                            "max_prompt_image_size" : 3145728,
                            "max_prompt_images" : 1,
                            "supported_media_types" : [
                                "image/jpeg",
                                "image/png",
                                "image/webp",
                                "image/gif"
                            ]
                        }
                    },
                    "object" : "model_capabilities",
                    "supports" : {
                        "parallel_tool_calls" : true,
                        "reasoning_effort" : [
                            "low",
                            "medium",
                            "high"
                        ],
                        "streaming" : true,
                        "structured_outputs" : true,
                        "tool_calls" : true,
                        "vision" : true
                    },
                    "tokenizer" : "o200k_base",
                    "type" : "chat"
                },
                "id" : "gpt-5.1-codex",
                "model_picker_category" : "powerful",
                "model_picker_enabled" : true,
                "name" : "GPT-5.1-Codex",
                "object" : "model",
                "policy" : {
                    "state" : "enabled",
                    "terms" : "Enable access to the latest GPT-5.1-Codex model from OpenAI. [Learn more about how GitHub Copilot serves GPT-5.1-Codex](https://gh.io/copilot-openai)."
                },
                "preview" : false,
                "supported_endpoints" : [
                    "/responses"
                ],
                "vendor" : "OpenAI",
                "version" : "gpt-5.1-codex"
            }
        ]
    }
    """
    let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: Data(json.utf8))
    #expect(response.allModels.count == 2)

    let gpt4o = response.allModels[0]
    #expect(gpt4o.isUsableForChat == false)
    #expect(gpt4o.modelPickerEnabled == false)

    let codex = response.allModels[1]
    #expect(codex.isUsableForChat == true)
    #expect(codex.modelPickerEnabled == true)
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
        "supported_endpoints": ["/chat/completions", "/responses"],
        "model_picker_enabled": true,
        "policy": {"state": "enabled"}
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
    #expect(model.modelPickerEnabled == true)
    #expect(model.policy?.state == "enabled")
    #expect(model.policy?.isEnabled == true)
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
    #expect(model.modelPickerEnabled == true)
    #expect(model.policy == nil)
}

@Test func copilotModelGracefullyHandlesUnexpectedCapabilitiesType() throws {
    let json = """
    {"id": "test-model", "capabilities": "unexpected-string"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.capabilities == nil)
}

@Test func copilotModelGracefullyHandlesUnexpectedSupportedEndpointsType() throws {
    let json = """
    {"id": "test-model", "supported_endpoints": "not-an-array"}
    """
    let model = try JSONDecoder().decode(CopilotModel.self, from: Data(json.utf8))
    #expect(model.supportedEndpoints == nil)
}

@Test func copilotModelCapabilitiesDecodesWithAllFieldsNil() throws {
    let json = "{}"
    let capabilities = try JSONDecoder().decode(CopilotModelCapabilities.self, from: Data(json.utf8))
    #expect(capabilities.family == nil)
    #expect(capabilities.type == nil)
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

@Test func isUsableForChatReturnsTrueForChatCompletionsEndpoint() {
    let model = CopilotModel(id: "gpt-4o", supportedEndpoints: ["/chat/completions"])
    #expect(model.isUsableForChat == true)
}

@Test func isUsableForChatReturnsTrueForResponsesEndpoint() {
    let model = CopilotModel(id: "codex-model", supportedEndpoints: ["/responses"])
    #expect(model.isUsableForChat == true)
}

@Test func isUsableForChatReturnsTrueForBothEndpoints() {
    let model = CopilotModel(id: "gpt-4o", supportedEndpoints: ["/chat/completions", "/responses"])
    #expect(model.isUsableForChat == true)
}

@Test func isUsableForChatReturnsFalseForEmbeddingsOnly() {
    let model = CopilotModel(id: "text-embedding-ada-002", supportedEndpoints: ["/embeddings"])
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsFalseForEmptyEndpoints() {
    let model = CopilotModel(id: "empty-model", supportedEndpoints: [])
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsFalseWhenEndpointsNilAndNoCapabilities() {
    let model = CopilotModel(id: "unknown-model")
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsTrueWhenEndpointsNilAndChatType() {
    let capabilities = CopilotModelCapabilities(type: "chat")
    let model = CopilotModel(id: "chat-model", capabilities: capabilities)
    #expect(model.isUsableForChat == true)
}

@Test func isUsableForChatReturnsFalseWhenEndpointsNilAndEmbeddingsType() {
    let capabilities = CopilotModelCapabilities(type: "embeddings")
    let model = CopilotModel(id: "embedding-model", capabilities: capabilities)
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsFalseWhenModelPickerDisabled() {
    let model = CopilotModel(id: "hidden-model", supportedEndpoints: ["/chat/completions"], modelPickerEnabled: false)
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsFalseWhenPolicyIsPending() {
    let policy = CopilotModelPolicy(state: "pending")
    let model = CopilotModel(id: "pending-model", supportedEndpoints: ["/chat/completions"], policy: policy)
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsFalseWhenPolicyRequiresConsent() {
    let policy = CopilotModelPolicy(state: "requires_consent")
    let model = CopilotModel(id: "consent-model", supportedEndpoints: ["/chat/completions"], policy: policy)
    #expect(model.isUsableForChat == false)
}

@Test func isUsableForChatReturnsTrueWhenPolicyIsEnabled() {
    let policy = CopilotModelPolicy(state: "enabled")
    let model = CopilotModel(id: "enabled-model", supportedEndpoints: ["/chat/completions"], policy: policy)
    #expect(model.isUsableForChat == true)
}

@Test func isUsableForChatReturnsTrueWhenNoPolicyPresent() {
    let model = CopilotModel(id: "no-policy-model", supportedEndpoints: ["/chat/completions"])
    #expect(model.isUsableForChat == true)
}
