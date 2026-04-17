@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Suite("SSEEventNormalizer")
struct SSEEventNormalizerTests {
    private let normalizer = SSEEventNormalizer()

    @Test func addsObjectFieldWhenMissing() {
        let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1772507025,"id":"msg_abc","model":"claude-haiku-4.5"}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
        #expect(json["id"] as? String == "msg_abc")
        #expect(json["model"] as? String == "claude-haiku-4.5")
    }

    @Test func preservesExistingObjectField() {
        let input = #"{"choices":[],"created":1234567890,"id":"chatcmpl-123","model":"gpt-4","object":"chat.completion.chunk"}"#

        let result = normalizer.normalizeEventData(input)

        #expect(result == input)
        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
    }

    @Test func returnsOriginalForInvalidJSON() {
        let input = "not valid json"

        let result = normalizer.normalizeEventData(input)

        #expect(result == input)
    }

    @Test func handlesDoneSignal() {
        let input = "[DONE]"

        let result = normalizer.normalizeEventData(input)

        #expect(result == input)
    }

    @Test func preservesAllExistingFields() {
        let input = #"{"choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"function":{"name":"XcodeUpdate"},"id":"toolu_abc","index":1,"type":"function"}]},"finish_reason":null}],"created":1772507629,"id":"msg_xyz","model":"claude-sonnet-4.5"}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
        #expect(json["id"] as? String == "msg_xyz")
        #expect(json["model"] as? String == "claude-sonnet-4.5")
        #expect((json["choices"] as? [[String: Any]])?.count == 1)

        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
        let function = toolCall["function"] as! [String: Any]
        #expect(function["arguments"] as? String == "")
    }

    @Test func addsEmptyArgumentsWhenMissingFromToolCallFunction() {
        let input = #"{"model":"claude-sonnet-4.5","id":"msg_vrtx_01","created":1772509504,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"id":"toolu_vrtx_01","function":{"name":"BuildProject"},"type":"function","index":0}]}}]}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
        let function = toolCall["function"] as! [String: Any]
        #expect(function["arguments"] as? String == "")
        #expect(function["name"] as? String == "BuildProject")
    }

    @Test func preservesExistingArgumentsInToolCallFunction() {
        let input = #"{"model":"claude-sonnet-4.5","id":"msg_001","created":1234567890,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"id":"call_1","function":{"name":"XcodeGrep","arguments":"{\"pattern\":"},"type":"function","index":0}]}}]}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        let toolCall = (delta["tool_calls"] as! [[String: Any]])[0]
        let function = toolCall["function"] as! [String: Any]
        #expect(function["arguments"] as? String == "{\"pattern\":")
    }

    @Test func handlesMultipleToolCallsInSingleChunk() {
        let input = #"{"model":"claude-sonnet-4.5","id":"msg_002","created":1234567890,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"id":"call_1","function":{"name":"ToolA"},"type":"function","index":0},{"id":"call_2","function":{"name":"ToolB","arguments":"{}"},"type":"function","index":1}]}}]}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        let toolCalls = delta["tool_calls"] as! [[String: Any]]
        #expect(toolCalls.count == 2)
        let func0 = toolCalls[0]["function"] as! [String: Any]
        let func1 = toolCalls[1]["function"] as! [String: Any]
        #expect(func0["arguments"] as? String == "")
        #expect(func1["arguments"] as? String == "{}")
    }

    @Test func doesNotModifyChunksWithoutToolCalls() {
        let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1234567890,"id":"msg_003","model":"gpt-4"}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        #expect(delta["content"] as? String == "Hello")
        #expect(delta["tool_calls"] == nil)
    }

    @Test func fastExitWhenObjectPresentAndNoToolCalls() {
        let input = #"{"id":"chatcmpl-abc","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#

        let result = normalizer.normalizeEventData(input)

        #expect(result == input)
    }

    @Test func stringInjectionDoesNotParseJSON() {
        let input = #"{"id":"msg_abc","created":1700000000,"model":"claude-haiku-4.5","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#

        let result = normalizer.normalizeEventData(input)

        #expect(result.hasPrefix(#"{"object":"chat.completion.chunk","#))
        let expectedTail = String(input.dropFirst())
        #expect(result.hasSuffix(expectedTail))
        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
        #expect(json["id"] as? String == "msg_abc")
    }

    @Test func stringInjectionPreservesAllOriginalFields() {
        let input = #"{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}],"created":1772507025,"id":"msg_abc","model":"claude-haiku-4.5"}"#

        let result = normalizer.normalizeEventData(input)

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["object"] as? String == "chat.completion.chunk")
        #expect(json["id"] as? String == "msg_abc")
        #expect(json["model"] as? String == "claude-haiku-4.5")
        #expect(json["created"] as? Int == 1772507025)
        let choice = (json["choices"] as! [[String: Any]])[0]
        let delta = choice["delta"] as! [String: Any]
        #expect(delta["content"] as? String == "Hello")
    }
}