struct ExtractedToolCall: Sendable {
    let callId: String
    let name: String
    let arguments: String
}

struct ExtractedCompletedContent: Sendable {
    let text: String
    let toolCalls: [ExtractedToolCall]
}