import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func currentTimestampReturnsReasonableValue() {
    let before = Int(Date.now.timeIntervalSince1970)
    let timestamp = ChatCompletionChunk.currentTimestamp()
    let after = Int(Date.now.timeIntervalSince1970)
    #expect(timestamp >= before)
    #expect(timestamp <= after)
}

@Test func currentTimestampIsPositive() {
    let timestamp = ChatCompletionChunk.currentTimestamp()
    #expect(timestamp > 0)
}

@Test func makeCompletionIdStartsWithExpectedPrefix() {
    let id = ChatCompletionChunk.makeCompletionId()
    #expect(id.hasPrefix("chatcmpl-"))
}

@Test func makeCompletionIdContainsTimestampAfterPrefix() {
    let id = ChatCompletionChunk.makeCompletionId()
    let numericPart = String(id.dropFirst("chatcmpl-".count))
    #expect(Int(numericPart) != nil)
}

@Test func makeCompletionIdIsUniqueAcrossCalls() async throws {
    let id1 = ChatCompletionChunk.makeCompletionId()
    try await Task.sleep(for: .milliseconds(2))
    let id2 = ChatCompletionChunk.makeCompletionId()
    #expect(id1 != id2)
}

@Test func makeRoleDeltaHasAssistantRole() {
    let chunk = ChatCompletionChunk.makeRoleDelta(id: "test-id", model: "gpt-4")
    #expect(chunk.id == "test-id")
    #expect(chunk.model == "gpt-4")
    #expect(chunk.object == "chat.completion.chunk")
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices[0].delta?.role == .assistant)
    #expect(chunk.choices[0].delta?.content == nil)
    #expect(chunk.choices[0].finishReason == nil)
}

@Test func makeContentDeltaHasContent() {
    let chunk = ChatCompletionChunk.makeContentDelta(id: "test-id", model: "gpt-4", content: "Hello")
    #expect(chunk.id == "test-id")
    #expect(chunk.model == "gpt-4")
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices[0].delta?.content == "Hello")
    #expect(chunk.choices[0].delta?.role == nil)
    #expect(chunk.choices[0].finishReason == nil)
}

@Test func makeContentDeltaWithEmptyContent() {
    let chunk = ChatCompletionChunk.makeContentDelta(id: "id", model: "m", content: "")
    #expect(chunk.choices[0].delta?.content == "")
}

@Test func makeToolCallDeltaHasToolCalls() {
    let toolCall = ToolCall(
        index: 0,
        id: "call_1",
        type: "function",
        function: ToolCallFunction(name: "search", arguments: "{}")
    )
    let chunk = ChatCompletionChunk.makeToolCallDelta(id: "test-id", model: "gpt-4", toolCalls: [toolCall])
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices[0].delta?.toolCalls?.count == 1)
    #expect(chunk.choices[0].delta?.toolCalls?[0].function.name == "search")
    #expect(chunk.choices[0].finishReason == nil)
}

@Test func makeStopDeltaHasStopFinishReason() {
    let chunk = ChatCompletionChunk.makeStopDelta(id: "test-id", model: "gpt-4")
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices[0].finishReason == "stop")
    #expect(chunk.choices[0].delta?.content == nil)
    #expect(chunk.choices[0].delta?.role == nil)
}

@Test func chunkInitDefaultValues() {
    let chunk = ChatCompletionChunk(
        id: "id-1",
        model: "model-1",
        choices: []
    )
    #expect(chunk.id == "id-1")
    #expect(chunk.object == "chat.completion.chunk")
    #expect(chunk.model == "model-1")
    #expect(chunk.choices.isEmpty)
    #expect(chunk.systemFingerprint == nil)
    #expect(chunk.created > 0)
}

@Test func chunkEncodesAndDecodesRoundTrip() throws {
    let original = ChatCompletionChunk(
        id: "chatcmpl-123",
        created: 1700000000,
        model: "gpt-4",
        choices: [
            ChunkChoice(
                index: 0,
                delta: ChunkDelta(role: .assistant, content: "Hi"),
                finishReason: nil
            )
        ],
        systemFingerprint: "fp_abc"
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.object == original.object)
    #expect(decoded.created == original.created)
    #expect(decoded.model == original.model)
    #expect(decoded.choices.count == 1)
    #expect(decoded.choices[0].delta?.role == .assistant)
    #expect(decoded.choices[0].delta?.content == "Hi")
    #expect(decoded.systemFingerprint == "fp_abc")
}

@Test func chunkChoiceDefaultIndex() {
    let choice = ChunkChoice()
    #expect(choice.index == 0)
    #expect(choice.delta == nil)
    #expect(choice.finishReason == nil)
}

@Test func chunkDeltaWithAllFieldsNil() {
    let delta = ChunkDelta()
    #expect(delta.role == nil)
    #expect(delta.content == nil)
    #expect(delta.toolCalls == nil)
}

@Test func chunkUsesSnakeCaseCodingKeys() throws {
    let chunk = ChatCompletionChunk(
        id: "id",
        created: 100,
        model: "m",
        choices: [ChunkChoice(finishReason: "stop")],
        systemFingerprint: "fp"
    )

    let data = try JSONEncoder().encode(chunk)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["system_fingerprint"] as? String == "fp")
    let choices = json?["choices"] as? [[String: Any]]
    #expect(choices?[0]["finish_reason"] as? String == "stop")
}