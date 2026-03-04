import Foundation

struct WindowTabEntry {
    let tabIdentifier: String
    let workspacePath: String
}

struct TabIdentifierResolver {
    static func resolve(from errorText: String, filePath: String?) -> String? {
        let entries = parseWindowEntries(from: errorText)
        guard !entries.isEmpty else { return nil }

        if let filePath, !filePath.isEmpty {
            if let match = bestMatch(for: filePath, in: entries) {
                return match
            }
        }

        return entries.first?.tabIdentifier
    }

    static func isTabIdentifierError(_ text: String) -> Bool {
        text.hasPrefix("Error: Valid tabIdentifier required")
    }

    private static func parseWindowEntries(from text: String) -> [WindowTabEntry] {
        var entries: [WindowTabEntry] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }

            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let tabId = extractValue(key: "tabIdentifier", from: content),
                  let workspacePath = extractValue(key: "workspacePath", from: content)
            else { continue }

            entries.append(WindowTabEntry(tabIdentifier: tabId, workspacePath: workspacePath))
        }

        return entries
    }

    private static func extractValue(key: String, from text: String) -> String? {
        let prefix = "\(key): "
        guard let keyRange = text.range(of: prefix) else { return nil }

        let afterKey = String(text[keyRange.upperBound...])
        if let commaRange = afterKey.range(of: ", ") {
            return String(afterKey[..<commaRange.lowerBound])
        }
        return afterKey.trimmingCharacters(in: .whitespaces)
    }

    private static func bestMatch(for filePath: String, in entries: [WindowTabEntry]) -> String? {
        var bestEntry: WindowTabEntry?
        var bestMatchLength = 0

        for entry in entries {
            let workspaceDir = (entry.workspacePath as NSString).deletingLastPathComponent

            if filePath.hasPrefix(workspaceDir), workspaceDir.count > bestMatchLength {
                bestEntry = entry
                bestMatchLength = workspaceDir.count
                continue
            }

            let dirName = (workspaceDir as NSString).lastPathComponent
            if !dirName.isEmpty, filePath.hasPrefix(dirName + "/") || filePath == dirName,
               dirName.count > bestMatchLength {
                bestEntry = entry
                bestMatchLength = dirName.count
            }
        }

        return bestEntry?.tabIdentifier
    }
}