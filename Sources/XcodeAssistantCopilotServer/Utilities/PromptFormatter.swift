import Foundation

public enum PromptFormatterError: Error, CustomStringConvertible {
    case contentExtractionFailed(String)

    public var description: String {
        switch self {
        case .contentExtractionFailed(let message):
            "Failed to extract content: \(message)"
        }
    }
}

public struct PromptFormatter: Sendable {
    public init() {}

    public func formatPrompt(
        messages: [ChatCompletionMessage],
        excludedFilePatterns: [String] = []
    ) throws -> String {
        var parts: [String] = []

        for message in messages {
            guard let role = message.role else { continue }

            let content: String
            do {
                content = try message.extractContentText()
            } catch {
                throw PromptFormatterError.contentExtractionFailed(error.localizedDescription)
            }

            switch role {
            case .system, .developer:
                continue

            case .user:
                let filtered = filterExcludedFiles(content, patterns: excludedFilePatterns)
                parts.append("[User]: \(filtered)")

            case .assistant:
                if !content.isEmpty {
                    parts.append("[Assistant]: \(content)")
                }
                if let toolCalls = message.toolCalls {
                    for toolCall in toolCalls {
                        parts.append(
                            "[Assistant called tool \(toolCall.function.name) with args: \(toolCall.function.arguments)]"
                        )
                    }
                }

            case .tool:
                let toolCallId = message.toolCallId ?? "unknown"
                parts.append("[Tool result for \(toolCallId)]: \(content)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    public func extractSystemMessages(from messages: [ChatCompletionMessage]) throws -> String? {
        var systemParts: [String] = []

        for message in messages {
            guard let role = message.role,
                  role == .system || role == .developer else {
                continue
            }

            let content = try message.extractContentText()
            if !content.isEmpty {
                systemParts.append(content)
            }
        }

        guard !systemParts.isEmpty else { return nil }
        return systemParts.joined(separator: "\n\n")
    }

    public func filterExcludedFiles(_ text: String, patterns: [String]) -> String {
        guard !patterns.isEmpty else { return text }

        var result = text
        for pattern in patterns {
            result = removeCodeBlocksMatching(result, pattern: pattern)
        }
        return result
    }

    private func removeCodeBlocksMatching(_ text: String, pattern: String) -> String {
        let lowercasedPattern = pattern.lowercased()
        var result = ""
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            guard let ticksRange = remaining.range(of: "```") else {
                result += remaining
                break
            }

            result += remaining[remaining.startIndex..<ticksRange.lowerBound]

            let afterTicks = remaining[ticksRange.upperBound...]
            guard let headerEnd = afterTicks.firstIndex(of: "\n") else {
                result += remaining[ticksRange.lowerBound...]
                break
            }

            let header = String(afterTicks[afterTicks.startIndex..<headerEnd])

            guard let closingRange = afterTicks[afterTicks.index(after: headerEnd)...]
                .range(of: "```") else {
                result += remaining[ticksRange.lowerBound...]
                break
            }

            let blockEnd = closingRange.upperBound
            var afterBlock = afterTicks[blockEnd...]
            if afterBlock.first == "\n" {
                afterBlock = afterBlock.dropFirst()
            }

            let hasColon = header.contains(":")
            let matchesPattern = header.lowercased().contains(lowercasedPattern)

            if hasColon && matchesPattern {
                remaining = afterBlock
            } else {
                let fullBlock = String(remaining[ticksRange.lowerBound..<blockEnd])
                result += fullBlock
                remaining = afterBlock
            }
        }

        return result
    }
}