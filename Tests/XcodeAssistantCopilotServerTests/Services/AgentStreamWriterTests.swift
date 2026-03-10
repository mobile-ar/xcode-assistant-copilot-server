@testable import XcodeAssistantCopilotServer
import Foundation
import NIOCore
import Testing

@Suite struct AgentStreamWriterTests {
    private func makeWriter() -> (AgentStreamWriter, AsyncStream<ByteBuffer>) {
        var continuation: AsyncStream<ByteBuffer>.Continuation!
        let stream = AsyncStream<ByteBuffer> { continuation = $0 }
        let writer = AgentStreamWriter(
            continuation: continuation,
            completionId: "test-id",
            model: "test-model"
        )
        return (writer, stream)
    }

    private func collectChunks(
        from stream: AsyncStream<ByteBuffer>,
        triggeringWith block: () -> Void
    ) async -> [String] {
        block()
        var results: [String] = []
        for await buffer in stream {
            if let string = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                results.append(string)
            }
        }
        return results
    }

    private func decodedSSEData(from sseLines: [String]) -> [String] {
        sseLines.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            return String(line.dropFirst("data: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @Test func writeRoleDeltaEmitsRoleChunk() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeRoleDelta()
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let roleChunk = dataLines.first { $0 != "[DONE]" }
        #expect(roleChunk != nil)
        #expect(roleChunk?.contains("\"role\"") == true)
        #expect(roleChunk?.contains("assistant") == true)
    }

    @Test func writeRoleDeltaUsesCorrectCompletionId() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeRoleDelta()
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let roleChunk = dataLines.first { $0 != "[DONE]" }
        #expect(roleChunk?.contains("test-id") == true)
    }

    @Test func writeProgressTextEmitsContentDeltaChunk() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeProgressText("hello progress")
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let contentChunk = dataLines.first { $0 != "[DONE]" }
        #expect(contentChunk?.contains("hello progress") == true)
    }

    @Test func writeProgressTextEmitsNothing_WhenTextIsEmpty() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeProgressText("")
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let nonDone = dataLines.filter { $0 != "[DONE]" }
        #expect(nonDone.isEmpty)
    }

    @Test func writeFinalContentEmitsContentAndStopChunks() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeFinalContent("final answer", toolCalls: nil, hadToolUse: false)
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let nonDone = dataLines.filter { $0 != "[DONE]" }
        #expect(nonDone.contains { $0.contains("final answer") })
        #expect(nonDone.contains { $0.contains("stop") })
    }

    @Test func writeFinalContentWithToolCallsEmitsToolCallChunkAndToolCallsFinishReason() async {
        let (writer, stream) = makeWriter()
        let toolCall = ToolCall(
            index: 0,
            id: "call_1",
            type: "function",
            function: ToolCallFunction(name: "bash", arguments: "{}")
        )

        let chunks = await collectChunks(from: stream) {
            writer.writeFinalContent("", toolCalls: [toolCall], hadToolUse: false)
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let nonDone = dataLines.filter { $0 != "[DONE]" }
        #expect(nonDone.contains { $0.contains("tool_calls") })
    }

    @Test func writeFinalContentWithHadToolUseEmitsSeparatorBeforeContent() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeFinalContent("final", toolCalls: nil, hadToolUse: true)
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let allContent = dataLines
            .filter { $0 != "[DONE]" }
            .compactMap { line -> String? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else { return nil }
                return content
            }
            .joined()

        #expect(allContent.contains("---"))
        #expect(allContent.contains("final"))
    }

    @Test func writeFinalContentWithoutHadToolUseDoesNotEmitSeparator() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeFinalContent("final", toolCalls: nil, hadToolUse: false)
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let allContent = dataLines
            .filter { $0 != "[DONE]" }
            .compactMap { line -> String? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else { return nil }
                return content
            }
            .joined()

        #expect(!allContent.contains("---"))
        #expect(allContent.contains("final"))
    }

    @Test func finishEmitsDoneEvent() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.finish()
        }

        #expect(chunks.contains { $0.contains("[DONE]") })
    }

    @Test func multipleProgressTextsAreAllEmitted() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeProgressText("first")
            writer.writeProgressText("second")
            writer.writeProgressText("third")
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let contentPieces = dataLines
            .filter { $0 != "[DONE]" }
            .compactMap { line -> String? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else { return nil }
                return content
            }

        #expect(contentPieces.contains("first"))
        #expect(contentPieces.contains("second"))
        #expect(contentPieces.contains("third"))
    }

    @Test func writeFinalContentEmptyTextWithNoToolCallsEmitsOnlyStop() async {
        let (writer, stream) = makeWriter()

        let chunks = await collectChunks(from: stream) {
            writer.writeFinalContent("", toolCalls: nil, hadToolUse: false)
            writer.finish()
        }

        let dataLines = decodedSSEData(from: chunks)
        let nonDone = dataLines.filter { $0 != "[DONE]" }
        #expect(nonDone.contains { $0.contains("stop") })
        #expect(nonDone.allSatisfy { !$0.contains("tool_calls") })
    }
}