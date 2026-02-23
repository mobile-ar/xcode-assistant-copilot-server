import Testing
import Foundation
@testable import XcodeAssistantCopilotServer

@Test func responsesMessageEncodesCorrectly() throws {
    let message = ResponsesMessage(role: "user", content: "Hello world")
    let data = try JSONEncoder().encode(message)
    let dict = try JSONDecoder().decode([String: String].self, from: data)
    #expect(dict["role"] == "user")
    #expect(dict["content"] == "Hello world")
}

@Test func responsesFunctionCallEncodesCorrectly() throws {
    let call = ResponsesFunctionCall(
        id: "fc_123",
        callId: "call_456",
        name: "get_weather",
        arguments: "{\"city\":\"NYC\"}"
    )
    let data = try JSONEncoder().encode(call)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call")
    #expect(dict?["id"] as? String == "fc_123")
    #expect(dict?["call_id"] as? String == "call_456")
    #expect(dict?["name"] as? String == "get_weather")
    #expect(dict?["arguments"] as? String == "{\"city\":\"NYC\"}")
}

@Test func responsesFunctionCallOutputEncodesCorrectly() throws {
    let output = ResponsesFunctionCallOutput(callId: "call_789", output: "Sunny, 72°F")
    let data = try JSONEncoder().encode(output)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call_output")
    #expect(dict?["call_id"] as? String == "call_789")
    #expect(dict?["output"] as? String == "Sunny, 72°F")
}

@Test func responsesAPIToolEncodesCorrectly() throws {
    let tool = ResponsesAPITool(
        name: "search",
        description: "Search the web",
        parameters: [
            "type": AnyCodable(.string("object")),
            "properties": AnyCodable(.dictionary([
                "query": AnyCodable(.dictionary([
                    "type": AnyCodable(.string("string"))
                ]))
            ]))
        ]
    )
    let data = try JSONEncoder().encode(tool)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function")
    #expect(dict?["name"] as? String == "search")
    #expect(dict?["description"] as? String == "Search the web")
    #expect(dict?["parameters"] != nil)
}

@Test func responsesAPIToolEncodesWithoutOptionalFields() throws {
    let tool = ResponsesAPITool(name: "simple_tool")
    let data = try JSONEncoder().encode(tool)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function")
    #expect(dict?["name"] as? String == "simple_tool")
    #expect(dict?["description"] == nil || dict?["description"] is NSNull)
    #expect(dict?["parameters"] == nil || dict?["parameters"] is NSNull)
}

@Test func responsesReasoningEncodesCorrectly() throws {
    let reasoning = ResponsesReasoning(effort: "high")
    let data = try JSONEncoder().encode(reasoning)
    let dict = try JSONDecoder().decode([String: String].self, from: data)
    #expect(dict["effort"] == "high")
}

@Test func responsesInputItemMessageEncodesCorrectly() throws {
    let item = ResponsesInputItem.message(ResponsesMessage(role: "user", content: "Hi"))
    let data = try JSONEncoder().encode(item)
    let dict = try JSONDecoder().decode([String: String].self, from: data)
    #expect(dict["role"] == "user")
    #expect(dict["content"] == "Hi")
}

@Test func responsesInputItemFunctionCallEncodesCorrectly() throws {
    let item = ResponsesInputItem.functionCall(ResponsesFunctionCall(
        id: "fc_1",
        callId: "call_1",
        name: "read_file",
        arguments: "{}"
    ))
    let data = try JSONEncoder().encode(item)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call")
    #expect(dict?["name"] as? String == "read_file")
}

@Test func responsesInputItemFunctionCallOutputEncodesCorrectly() throws {
    let item = ResponsesInputItem.functionCallOutput(ResponsesFunctionCallOutput(
        callId: "call_1",
        output: "file contents"
    ))
    let data = try JSONEncoder().encode(item)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call_output")
    #expect(dict?["call_id"] as? String == "call_1")
    #expect(dict?["output"] as? String == "file contents")
}

@Test func responsesAPIRequestEncodesMinimalRequest() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: [
            .message(ResponsesMessage(role: "user", content: "Hello"))
        ]
    )
    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["model"] as? String == "gpt-5.1-codex")
    #expect(dict?["stream"] as? Bool == true)
    let input = dict?["input"] as? [[String: Any]]
    #expect(input?.count == 1)
    #expect(input?[0]["role"] as? String == "user")
    #expect(input?[0]["content"] as? String == "Hello")
}

@Test func responsesAPIRequestEncodesFullRequest() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: [
            .message(ResponsesMessage(role: "user", content: "Read this file")),
            .functionCall(ResponsesFunctionCall(
                id: "fc_1",
                callId: "call_1",
                name: "read_file",
                arguments: "{\"path\":\"/tmp/test\"}"
            )),
            .functionCallOutput(ResponsesFunctionCallOutput(
                callId: "call_1",
                output: "file contents here"
            ))
        ],
        stream: true,
        instructions: "You are a coding assistant",
        tools: [ResponsesAPITool(name: "read_file", description: "Read a file")],
        toolChoice: AnyCodable(.string("auto")),
        reasoning: ResponsesReasoning(effort: "high")
    )

    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(dict?["model"] as? String == "gpt-5.1-codex")
    #expect(dict?["stream"] as? Bool == true)
    #expect(dict?["instructions"] as? String == "You are a coding assistant")
    #expect(dict?["tool_choice"] as? String == "auto")

    let reasoning = dict?["reasoning"] as? [String: Any]
    #expect(reasoning?["effort"] as? String == "high")

    let tools = dict?["tools"] as? [[String: Any]]
    #expect(tools?.count == 1)
    #expect(tools?[0]["name"] as? String == "read_file")

    let input = dict?["input"] as? [[String: Any]]
    #expect(input?.count == 3)
    #expect(input?[0]["role"] as? String == "user")
    #expect(input?[1]["type"] as? String == "function_call")
    #expect(input?[2]["type"] as? String == "function_call_output")
}

@Test func responsesAPIRequestOmitsNilFields() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: [.message(ResponsesMessage(role: "user", content: "Hi"))]
    )
    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(dict?["model"] != nil)
    #expect(dict?["input"] != nil)
    #expect(dict?["stream"] != nil)
    #expect(dict?.keys.contains("instructions") == false || dict?["instructions"] is NSNull)
    #expect(dict?.keys.contains("tools") == false || dict?["tools"] is NSNull)
    #expect(dict?.keys.contains("reasoning") == false || dict?["reasoning"] is NSNull)
}

@Test func responsesTextDeltaEventDecodesCorrectly() throws {
    let json = """
    {"delta":"Hello ","content_index":0,"output_index":0}
    """
    let event = try JSONDecoder().decode(ResponsesTextDeltaEvent.self, from: Data(json.utf8))
    #expect(event.delta == "Hello ")
    #expect(event.contentIndex == 0)
    #expect(event.outputIndex == 0)
}

@Test func responsesTextDeltaEventDecodesMinimal() throws {
    let json = """
    {"delta":"Hi"}
    """
    let event = try JSONDecoder().decode(ResponsesTextDeltaEvent.self, from: Data(json.utf8))
    #expect(event.delta == "Hi")
    #expect(event.contentIndex == nil)
    #expect(event.outputIndex == nil)
}

@Test func responsesOutputItemAddedEventDecodesFunctionCall() throws {
    let json = """
    {"output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_123","name":"get_weather","status":"in_progress"}}
    """
    let event = try JSONDecoder().decode(ResponsesOutputItemAddedEvent.self, from: Data(json.utf8))
    #expect(event.outputIndex == 0)
    #expect(event.item.type == "function_call")
    #expect(event.item.id == "fc_1")
    #expect(event.item.callId == "call_123")
    #expect(event.item.name == "get_weather")
    #expect(event.item.status == "in_progress")
}

@Test func responsesOutputItemAddedEventDecodesMessage() throws {
    let json = """
    {"output_index":0,"item":{"type":"message","id":"msg_1","status":"in_progress"}}
    """
    let event = try JSONDecoder().decode(ResponsesOutputItemAddedEvent.self, from: Data(json.utf8))
    #expect(event.outputIndex == 0)
    #expect(event.item.type == "message")
    #expect(event.item.callId == nil)
    #expect(event.item.name == nil)
}

@Test func responsesFunctionCallArgsDeltaEventDecodes() throws {
    let json = """
    {"delta":"{\\\"city\\\"","call_id":"call_123","output_index":0,"item_id":"fc_1"}
    """
    let event = try JSONDecoder().decode(ResponsesFunctionCallArgsDeltaEvent.self, from: Data(json.utf8))
    #expect(event.delta == "{\"city\"")
    #expect(event.callId == "call_123")
    #expect(event.outputIndex == 0)
    #expect(event.itemId == "fc_1")
}

@Test func responsesFunctionCallArgsDeltaEventDecodesMinimal() throws {
    let json = """
    {"delta":"{}"}
    """
    let event = try JSONDecoder().decode(ResponsesFunctionCallArgsDeltaEvent.self, from: Data(json.utf8))
    #expect(event.delta == "{}")
    #expect(event.callId == nil)
    #expect(event.outputIndex == nil)
    #expect(event.itemId == nil)
}

@Test func responsesFunctionCallArgsDoneEventDecodes() throws {
    let json = """
    {"arguments":"{\\\"city\\\":\\\"NYC\\\"}","call_id":"call_123","output_index":0,"item_id":"fc_1"}
    """
    let event = try JSONDecoder().decode(ResponsesFunctionCallArgsDoneEvent.self, from: Data(json.utf8))
    #expect(event.arguments == "{\"city\":\"NYC\"}")
    #expect(event.callId == "call_123")
    #expect(event.outputIndex == 0)
    #expect(event.itemId == "fc_1")
}

@Test func responsesCompletedEventDecodes() throws {
    let json = """
    {"response":{"id":"resp_abc123","status":"completed"}}
    """
    let event = try JSONDecoder().decode(ResponsesCompletedEvent.self, from: Data(json.utf8))
    #expect(event.response.id == "resp_abc123")
    #expect(event.response.status == "completed")
}

@Test func responsesCompletedEventDecodesWithOutput() throws {
    let json = """
    {"response":{"id":"resp_abc123","status":"completed","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Hello"}]}]}}
    """
    let event = try JSONDecoder().decode(ResponsesCompletedEvent.self, from: Data(json.utf8))
    #expect(event.response.id == "resp_abc123")
    #expect(event.response.status == "completed")
    #expect(event.response.output?.count == 1)
    #expect(event.response.output?[0].type == "message")
    #expect(event.response.output?[0].content?.count == 1)
    #expect(event.response.output?[0].content?[0].type == "output_text")
    #expect(event.response.output?[0].content?[0].text == "Hello")
}

@Test func responsesCompletedEventDecodesWithFunctionCallOutput() throws {
    let json = """
    {"response":{"id":"resp_abc","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"read_file","arguments":"{}"}]}}
    """
    let event = try JSONDecoder().decode(ResponsesCompletedEvent.self, from: Data(json.utf8))
    #expect(event.response.output?.count == 1)
    #expect(event.response.output?[0].type == "function_call")
    #expect(event.response.output?[0].callId == "call_1")
    #expect(event.response.output?[0].name == "read_file")
    #expect(event.response.output?[0].arguments == "{}")
}

@Test func responsesCompletedContentPartDecodes() throws {
    let json = """
    {"type":"output_text","text":"Hello world"}
    """
    let part = try JSONDecoder().decode(ResponsesCompletedContentPart.self, from: Data(json.utf8))
    #expect(part.type == "output_text")
    #expect(part.text == "Hello world")
}

@Test func responsesCompletedContentPartDecodesWithoutText() throws {
    let json = """
    {"type":"refusal"}
    """
    let part = try JSONDecoder().decode(ResponsesCompletedContentPart.self, from: Data(json.utf8))
    #expect(part.type == "refusal")
    #expect(part.text == nil)
}

@Test func responsesOutputItemDecodes() throws {
    let json = """
    {"type":"function_call","id":"fc_1","call_id":"call_abc","name":"tool_name","status":"completed"}
    """
    let item = try JSONDecoder().decode(ResponsesOutputItem.self, from: Data(json.utf8))
    #expect(item.type == "function_call")
    #expect(item.id == "fc_1")
    #expect(item.callId == "call_abc")
    #expect(item.name == "tool_name")
    #expect(item.status == "completed")
}

@Test func responsesOutputItemDecodesMinimal() throws {
    let json = """
    {"type":"message"}
    """
    let item = try JSONDecoder().decode(ResponsesOutputItem.self, from: Data(json.utf8))
    #expect(item.type == "message")
    #expect(item.id == nil)
    #expect(item.callId == nil)
    #expect(item.name == nil)
    #expect(item.status == nil)
}

@Test func responsesEventTypeRawValues() {
    #expect(ResponsesEventType.responseCreated.rawValue == "response.created")
    #expect(ResponsesEventType.outputItemAdded.rawValue == "response.output_item.added")
    #expect(ResponsesEventType.outputItemDone.rawValue == "response.output_item.done")
    #expect(ResponsesEventType.contentPartAdded.rawValue == "response.content_part.added")
    #expect(ResponsesEventType.contentPartDone.rawValue == "response.content_part.done")
    #expect(ResponsesEventType.outputTextDelta.rawValue == "response.output_text.delta")
    #expect(ResponsesEventType.outputTextDone.rawValue == "response.output_text.done")
    #expect(ResponsesEventType.functionCallArgumentsDelta.rawValue == "response.function_call_arguments.delta")
    #expect(ResponsesEventType.functionCallArgumentsDone.rawValue == "response.function_call_arguments.done")
    #expect(ResponsesEventType.responseCompleted.rawValue == "response.completed")
    #expect(ResponsesEventType.responseFailed.rawValue == "response.failed")
    #expect(ResponsesEventType.responseIncomplete.rawValue == "response.incomplete")
}

@Test func responsesEventTypeParsesFromString() {
    #expect(ResponsesEventType(rawValue: "response.output_text.delta") == .outputTextDelta)
    #expect(ResponsesEventType(rawValue: "response.completed") == .responseCompleted)
    #expect(ResponsesEventType(rawValue: "response.output_item.added") == .outputItemAdded)
    #expect(ResponsesEventType(rawValue: "response.function_call_arguments.delta") == .functionCallArgumentsDelta)
    #expect(ResponsesEventType(rawValue: "response.function_call_arguments.done") == .functionCallArgumentsDone)
    #expect(ResponsesEventType(rawValue: "unknown.event.type") == nil)
}

@Test func responsesAPIRequestEncodesStreamFalse() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: [.message(ResponsesMessage(role: "user", content: "Hi"))],
        stream: false
    )
    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["stream"] as? Bool == false)
}

@Test func responsesAPIRequestEncodesEmptyInput() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: []
    )
    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let input = dict?["input"] as? [Any]
    #expect(input?.count == 0)
}

@Test func responsesAPIRequestEncodesToolChoiceObject() throws {
    let toolChoice = AnyCodable(.dictionary([
        "type": AnyCodable(.string("function")),
        "name": AnyCodable(.string("get_weather"))
    ]))
    let request = ResponsesAPIRequest(
        model: "gpt-5.1-codex",
        input: [.message(ResponsesMessage(role: "user", content: "Weather?"))],
        toolChoice: toolChoice
    )
    let data = try JSONEncoder().encode(request)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let tc = dict?["tool_choice"] as? [String: Any]
    #expect(tc?["type"] as? String == "function")
    #expect(tc?["name"] as? String == "get_weather")
}

@Test func responsesReasoningEffortValues() throws {
    let efforts = ["low", "medium", "high", "xhigh"]
    for effort in efforts {
        let reasoning = ResponsesReasoning(effort: effort)
        let data = try JSONEncoder().encode(reasoning)
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        #expect(dict["effort"] == effort)
    }
}

@Test func responsesFunctionCallSetsTypeAutomatically() throws {
    let call = ResponsesFunctionCall(
        id: "fc_1",
        callId: "call_1",
        name: "my_tool",
        arguments: "{}"
    )
    #expect(call.type == "function_call")

    let data = try JSONEncoder().encode(call)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call")
}

@Test func responsesFunctionCallOutputSetsTypeAutomatically() throws {
    let output = ResponsesFunctionCallOutput(callId: "call_1", output: "result")
    #expect(output.type == "function_call_output")

    let data = try JSONEncoder().encode(output)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function_call_output")
}

@Test func responsesAPIToolSetsTypeAutomatically() throws {
    let tool = ResponsesAPITool(name: "my_tool")
    #expect(tool.type == "function")

    let data = try JSONEncoder().encode(tool)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["type"] as? String == "function")
}

@Test func responsesTextDeltaEventDecodesUnicodeContent() throws {
    let json = """
    {"delta":"こんにちは 🌍 café"}
    """
    let event = try JSONDecoder().decode(ResponsesTextDeltaEvent.self, from: Data(json.utf8))
    #expect(event.delta == "こんにちは 🌍 café")
}

@Test func responsesCompletedResponseDecodesFailedStatus() throws {
    let json = """
    {"id":"resp_fail","status":"failed"}
    """
    let response = try JSONDecoder().decode(ResponsesCompletedResponse.self, from: Data(json.utf8))
    #expect(response.id == "resp_fail")
    #expect(response.status == "failed")
    #expect(response.output == nil)
}

@Test func responsesCompletedResponseDecodesIncompleteStatus() throws {
    let json = """
    {"id":"resp_inc","status":"incomplete","output":[]}
    """
    let response = try JSONDecoder().decode(ResponsesCompletedResponse.self, from: Data(json.utf8))
    #expect(response.id == "resp_inc")
    #expect(response.status == "incomplete")
    #expect(response.output?.isEmpty == true)
}

@Test func responsesMessageEncodesAllRoles() throws {
    let roles = ["user", "assistant", "developer"]
    for role in roles {
        let message = ResponsesMessage(role: role, content: "test")
        let data = try JSONEncoder().encode(message)
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        #expect(dict["role"] == role)
    }
}

@Test func responsesFunctionCallEncodesEmptyArguments() throws {
    let call = ResponsesFunctionCall(
        id: "fc_1",
        callId: "call_1",
        name: "no_args_tool",
        arguments: ""
    )
    let data = try JSONEncoder().encode(call)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(dict?["arguments"] as? String == "")
}