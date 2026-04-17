import Foundation

public struct ConversationContextManager: Sendable {
    private let logger: LoggerProtocol
    private static let truncationPreviewLength = 200

    public init(logger: LoggerProtocol) {
        self.logger = logger
    }

    public func compact(
        messages: [ChatCompletionMessage],
        tokenLimit: Int,
        recencyWindow: Int
    ) -> [ChatCompletionMessage] {
        let currentEstimate = estimateTokenCount(messages: messages)
        if currentEstimate <= tokenLimit {
            return messages
        }

        logger.info("Compacting conversation: \(currentEstimate) estimated tokens exceeds budget of \(tokenLimit)")

        let recentAssistantToolIndices = findRecentAssistantToolIndices(
            messages: messages,
            count: recencyWindow
        )
        let lastUserIndex = findLastUserMessageIndex(messages: messages)

        var compacted: [ChatCompletionMessage] = []
        for (index, message) in messages.enumerated() {
            let role = message.role
            if role == .system || role == .developer {
                compacted.append(message)
                continue
            }

            if index == lastUserIndex {
                compacted.append(message)
                continue
            }

            if recentAssistantToolIndices.contains(index) {
                compacted.append(message)
                continue
            }

            if role == .tool {
                let truncated = truncateToolResult(message: message)
                compacted.append(truncated)
                continue
            }

            if role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                let stripped = stripToolCallArguments(message: message, toolCalls: toolCalls)
                compacted.append(stripped)
                continue
            }

            compacted.append(message)
        }

        let estimatedTokens = estimateTokenCount(messages: compacted)
        if estimatedTokens > tokenLimit {
            logger.warn("Compacted conversation still exceeds token limit: \(estimatedTokens) estimated tokens > \(tokenLimit) limit")
        }

        return compacted
    }

    public func estimateTokenCount(messages: [ChatCompletionMessage]) -> Int {
        var totalChars = 0
        for message in messages {
            totalChars += extractContentLength(content: message.content)
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    totalChars += toolCall.function.arguments?.count ?? 0
                    totalChars += toolCall.function.name?.count ?? 0
                }
            }
            totalChars += message.name?.count ?? 0
            totalChars += message.role?.rawValue.count ?? 0
        }
        return totalChars / 4
    }

    public func estimateTokenCount(tools: [Tool]) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(tools) else {
            return 0
        }
        return data.count / 4
    }

    private func findLastUserMessageIndex(messages: [ChatCompletionMessage]) -> Int? {
        for index in messages.indices.reversed() {
            if messages[index].role == .user {
                return index
            }
        }
        return nil
    }

    private func findRecentAssistantToolIndices(
        messages: [ChatCompletionMessage],
        count: Int
    ) -> Set<Int> {
        var indices = Set<Int>()
        var pairsFound = 0

        var index = messages.count - 1
        while index >= 0, pairsFound < count {
            let message = messages[index]
            if message.role == .assistant {
                indices.insert(index)
                pairsFound += 1

                var toolIndex = index + 1
                while toolIndex < messages.count, messages[toolIndex].role == .tool {
                    indices.insert(toolIndex)
                    toolIndex += 1
                }
            }
            index -= 1
        }

        return indices
    }

    private func truncateToolResult(message: ChatCompletionMessage) -> ChatCompletionMessage {
        let originalLength = extractContentLength(content: message.content)
        let truncationNote = "[Result truncated — original \(originalLength) chars]"

        if originalLength <= truncationNote.count {
            return message
        }

        let replacement: String
        if originalLength > Self.truncationPreviewLength * 2 {
            let preview = extractContentPrefix(content: message.content, maxLength: Self.truncationPreviewLength)
            replacement = "\(preview)\n\n\(truncationNote)"
        } else {
            replacement = truncationNote
        }

        return ChatCompletionMessage(
            role: message.role,
            content: .text(replacement),
            name: message.name,
            toolCalls: message.toolCalls,
            toolCallId: message.toolCallId
        )
    }

    private func stripToolCallArguments(
        message: ChatCompletionMessage,
        toolCalls: [ToolCall]
    ) -> ChatCompletionMessage {
        let strippedCalls = toolCalls.map { call in
            ToolCall(
                index: call.index,
                id: call.id,
                type: call.type,
                function: ToolCallFunction(name: call.function.name, arguments: "{}")
            )
        }
        return ChatCompletionMessage(
            role: message.role,
            content: message.content,
            name: message.name,
            toolCalls: strippedCalls,
            toolCallId: message.toolCallId
        )
    }

    private func extractContentLength(content: MessageContent?) -> Int {
        guard let content else { return 0 }
        switch content {
        case .text(let text):
            return text.count
        case .parts(let parts):
            var total = 0
            for part in parts {
                total += part.text?.count ?? 0
            }
            return total
        case .none:
            return 0
        }
    }

    private func extractContentPrefix(content: MessageContent?, maxLength: Int) -> String {
        guard let content else { return "" }
        switch content {
        case .text(let text):
            if text.count <= maxLength { return text }
            return String(text.prefix(maxLength))
        case .parts(let parts):
            var result = ""
            for part in parts {
                if let text = part.text {
                    let remaining = maxLength - result.count
                    if remaining <= 0 { break }
                    result += String(text.prefix(remaining))
                }
            }
            return result
        case .none:
            return ""
        }
    }
}
