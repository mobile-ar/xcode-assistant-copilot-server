@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Test func chatCompletionChunkEncodesObjectField() throws {
    let chunk = ChatCompletionChunk.makeContentDelta(id: "chatcmpl-test", model: "gpt-4o", content: "hello")

    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func chatCompletionChunkDefaultObjectValue() {
    let chunk = ChatCompletionChunk(
        id: "chatcmpl-1",
        choices: [ChunkChoice(delta: ChunkDelta(content: "test"))]
    )
    #expect(chunk.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkCustomObjectValueRoundtrips() throws {
    let chunk = ChatCompletionChunk(
        id: "chatcmpl-1",
        object: "chat.completion.chunk",
        choices: [ChunkChoice(delta: ChunkDelta(content: "test"))]
    )
    let encoded = try JSONEncoder().encode(chunk)
    let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: encoded)
    #expect(decoded.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkDecodesObjectFieldFromUpstreamJSON() throws {
    let raw = #"{"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4o","choices":[]}"#
    let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: raw.data(using: .utf8)!)
    #expect(decoded.object == "chat.completion.chunk")
}

@Test func chatCompletionChunkMakeRoleDeltaEncodesObject() throws {
    let chunk = ChatCompletionChunk.makeRoleDelta(id: "chatcmpl-1", model: "gpt-4o")
    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func chatCompletionChunkMakeStopDeltaEncodesObject() throws {
    let chunk = ChatCompletionChunk.makeStopDelta(id: "chatcmpl-1", model: "gpt-4o")
    let encoded = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    #expect(json["object"] as? String == "chat.completion.chunk")
}