import Foundation
import NIOCore

protocol AgentStreamWriterProtocol: Sendable {
    func writeRoleDelta()
    func writeProgressText(_ text: String)
    func writeFinalContent(_ text: String, toolCalls: [ToolCall]?, hadToolUse: Bool)
    func finish()
}

struct AgentStreamWriter: AgentStreamWriterProtocol {
    private let continuation: AsyncStream<ByteBuffer>.Continuation
    private let completionId: String
    private let model: String
    private let encoder: JSONEncoder

    init(
        continuation: AsyncStream<ByteBuffer>.Continuation,
        completionId: String,
        model: String
    ) {
        self.continuation = continuation
        self.completionId = completionId
        self.model = model
        self.encoder = JSONEncoder()
    }

    func writeRoleDelta() {
        let chunk = ChatCompletionChunk.makeRoleDelta(id: completionId, model: model)
        emitChunk(chunk)
    }

    func writeProgressText(_ text: String) {
        guard !text.isEmpty else { return }
        let chunk = ChatCompletionChunk.makeContentDelta(
            id: completionId,
            model: model,
            content: text
        )
        emitChunk(chunk)
    }

    func writeFinalContent(_ text: String, toolCalls: [ToolCall]?, hadToolUse: Bool) {
        if !text.isEmpty {
            let separator = hadToolUse ? "\n\n---\n\n" : ""
            if hadToolUse {
                writeProgressText(separator)
            }
            let contentChunk = ChatCompletionChunk.makeContentDelta(
                id: completionId,
                model: model,
                content: text
            )
            emitChunk(contentChunk)
        }

        if let toolCalls, !toolCalls.isEmpty {
            let toolCallChunk = ChatCompletionChunk.makeToolCallDelta(
                id: completionId,
                model: model,
                toolCalls: toolCalls
            )
            emitChunk(toolCallChunk)

            let finishChunk = ChatCompletionChunk(
                id: completionId,
                model: model,
                choices: [ChunkChoice(delta: ChunkDelta(), finishReason: "tool_calls")]
            )
            emitChunk(finishChunk)
        } else {
            let stopChunk = ChatCompletionChunk.makeStopDelta(id: completionId, model: model)
            emitChunk(stopChunk)
        }
    }

    func finish() {
        continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
        continuation.finish()
    }

    private func emitChunk(_ chunk: ChatCompletionChunk) {
        guard let data = try? encoder.encode(chunk),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        continuation.yield(ByteBuffer(string: "data: \(jsonString)\n\n"))
    }
}