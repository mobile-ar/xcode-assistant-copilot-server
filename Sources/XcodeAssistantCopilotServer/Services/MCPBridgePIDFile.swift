import Foundation

public protocol MCPBridgePIDFileProtocol: Sendable {
    func write(pid: Int32) throws
    func read() -> Int32?
    func remove()
    func isProcessRunning(pid: Int32) -> Bool
}

public struct MCPBridgePIDFile: MCPBridgePIDFileProtocol, Sendable {
    private let filePath: String

    public init(directory: String? = nil) {
        let dir = directory ?? {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.xcode-assistant-copilot-server"
        }()
        self.filePath = "\(dir)/mcp-bridge.pid"
    }

    public func write(pid: Int32) throws {
        let directory = (filePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }
        let contents = "\(pid)\n"
        guard let data = contents.data(using: .utf8) else { return }
        FileManager.default.createFile(atPath: filePath, contents: data)
    }

    public func read() -> Int32? {
        guard FileManager.default.fileExists(atPath: filePath),
              let contents = FileManager.default.contents(atPath: filePath),
              let text = String(data: contents, encoding: .utf8)
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int32(trimmed)
    }

    public func remove() {
        try? FileManager.default.removeItem(atPath: filePath)
    }

    public func isProcessRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}