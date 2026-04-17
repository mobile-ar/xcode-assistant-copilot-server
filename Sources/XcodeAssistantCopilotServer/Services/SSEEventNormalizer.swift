import Foundation

protocol SSEEventNormalizerProtocol: Sendable {
    func normalizeEventData(_ data: String) -> String
}

struct SSEEventNormalizer: SSEEventNormalizerProtocol, Sendable {

    func normalizeEventData(_ data: String) -> String {
        let needsObject = !data.contains("\"object\"")
        let hasToolCalls = data.contains("\"tool_calls\"")

        if !needsObject && !hasToolCalls {
            return data
        }

        if needsObject && !hasToolCalls {
            guard data.hasPrefix("{") else { return data }
            return "{\"object\":\"chat.completion.chunk\"," + data.dropFirst()
        }

        return normalizeEventDataViaJSON(data, injectObject: needsObject)
    }

    private func normalizeEventDataViaJSON(_ data: String, injectObject: Bool) -> String {
        guard let jsonData = data.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return data
        }

        if injectObject {
            json["object"] = "chat.completion.chunk"
        }

        if let choices = json["choices"] as? [[String: Any]] {
            json["choices"] = choices.map { choice -> [String: Any] in
                var choice = choice
                if var delta = choice["delta"] as? [String: Any],
                   let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                    delta["tool_calls"] = toolCalls.map { toolCall -> [String: Any] in
                        var toolCall = toolCall
                        if var function = toolCall["function"] as? [String: Any],
                           function["arguments"] == nil {
                            function["arguments"] = ""
                            toolCall["function"] = function
                        }
                        return toolCall
                    }
                    choice["delta"] = delta
                }
                return choice
            }
        }

        guard let normalized = try? JSONSerialization.data(withJSONObject: json),
              let result = String(data: normalized, encoding: .utf8) else {
            return data
        }
        return result
    }
}