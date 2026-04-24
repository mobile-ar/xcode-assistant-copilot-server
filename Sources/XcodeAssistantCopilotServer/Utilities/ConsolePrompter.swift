import Foundation

public protocol ConsolePrompterProtocol: Sendable {
    func promptYesNo(_ message: String) -> Bool
}

public struct ConsolePrompter: ConsolePrompterProtocol {
    public init() {}

    public func promptYesNo(_ message: String) -> Bool {
        print(message + " [y/N] ", terminator: "")
        guard let input = readLine() else { return false }
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed == "y" || trimmed == "yes"
    }
}

struct SilentPrompter: ConsolePrompterProtocol {
    func promptYesNo(_ message: String) -> Bool {
        false
    }
}