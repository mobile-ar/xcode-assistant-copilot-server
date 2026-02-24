@testable import XcodeAssistantCopilotServer

final class MockMCPBridgeService: MCPBridgeServiceProtocol, @unchecked Sendable {
    var tools: [MCPTool] = []
    var callResults: [String: MCPToolResult] = [:]
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var listToolsCallCount = 0
    private(set) var calledTools: [(name: String, arguments: [String: AnyCodable])] = []
    var listToolsError: Error?
    var callToolError: Error?

    func start() async throws {
        startCallCount += 1
    }

    func stop() async throws {
        stopCallCount += 1
    }

    func listTools() async throws -> [MCPTool] {
        listToolsCallCount += 1
        if let error = listToolsError { throw error }
        return tools
    }

    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        calledTools.append((name: name, arguments: arguments))
        if let error = callToolError { throw error }
        guard let result = callResults[name] else {
            throw MCPToolError.toolNotFound(name)
        }
        return result
    }
}