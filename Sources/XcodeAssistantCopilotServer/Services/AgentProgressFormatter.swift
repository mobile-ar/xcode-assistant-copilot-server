import Foundation

struct AgentProgressFormatter: Sendable {
    private let logger: LoggerProtocol

    init(logger: LoggerProtocol) {
        self.logger = logger
    }

    func formattedToolCall(_ toolCall: ToolCall) -> String {
        let toolName = toolCall.function.name ?? "unknown"
        let arguments = parseJSON(toolCall.function.arguments)
        let filePath = extractFilePath(from: arguments)
        let contentValue = extractContent(from: arguments, excludingFilePath: filePath)

        var output = "\n**Running:** `\(toolName)`"

        if let filePath {
            output += " `\(filePath)`"
        }

        output += "\n"

        if let contentValue {
            let language = filePath.flatMap { languageFromExtension(of: $0) } ?? ""
            output += "```\(language)\n\(contentValue)\n```\n"
        }

        return output
    }

    func formattedToolResult(_ result: String) -> String {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "**✓** Done\n"
        }

        if let json = parseJSON(trimmed) {
            return formattedJSONResult(json, raw: trimmed)
        }

        if trimmed.hasPrefix("Error:") || trimmed.hasPrefix("Error executing tool") {
            return "**✗** \(trimmed)\n"
        }

        return ""
    }

    private func formattedJSONResult(_ json: [String: Any], raw: String) -> String {
        if let success = json["success"] as? Bool, !success {
            let message = json["message"] as? String ?? raw
            return "**✗** \(message)\n"
        }

        let errors = json["errors"] as? [Any] ?? []
        if !errors.isEmpty {
            let errorLines = errors.compactMap { entry -> String? in
                if let dict = entry as? [String: Any] {
                    return dict["message"] as? String ?? dict["description"] as? String
                }
                return "\(entry)"
            }
            let joined = errorLines.joined(separator: "\n")
            return "**✗** \(joined)\n"
        }

        let displayKeys = ["message", "buildResult", "result", "output", "text"]
        for key in displayKeys {
            if let value = json[key] as? String, !value.isEmpty {
                return "**✓** \(value)\n"
            }
        }

        return "**✓** Done\n"
    }

    private func extractFilePath(from arguments: [String: Any]?) -> String? {
        guard let arguments else { return nil }
        for key in ["filePath", "path", "sourceFilePath", "targetFilePath"] {
            if let value = arguments[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func extractContent(from arguments: [String: Any]?, excludingFilePath filePath: String?) -> String? {
        guard let arguments else { return nil }

        let skipKeys: Set<String> = ["filePath", "path", "sourceFilePath", "targetFilePath", "tabIdentifier"]

        var bestKey: String?
        var bestLength = 0

        for (key, value) in arguments {
            guard !skipKeys.contains(key), let string = value as? String else { continue }
            let length = string.count
            let isMultiline = string.contains("\n")
            if isMultiline && length > bestLength {
                bestKey = key
                bestLength = length
            }
        }

        if bestKey == nil {
            for (key, value) in arguments {
                guard !skipKeys.contains(key), let string = value as? String, !string.isEmpty else { continue }
                if string.count > bestLength {
                    bestKey = key
                    bestLength = string.count
                }
            }
        }

        guard let key = bestKey, let value = arguments[key] as? String else { return nil }
        return value
    }

    private func languageFromExtension(of path: String) -> String? {
        guard let dotIndex = path.lastIndex(of: ".") else { return nil }
        let ext = String(path[path.index(after: dotIndex)...]).lowercased()
        guard !ext.isEmpty, !ext.contains("/") else { return nil }
        return ext
    }

    private func parseJSON(_ string: String?) -> [String: Any]? {
        guard let string, !string.isEmpty else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json
        } catch {
            logger.debug("Failed to parse JSON in progress formatter: \(error.localizedDescription)")
            return nil
        }
    }
}