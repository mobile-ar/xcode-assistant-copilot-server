@testable import XcodeAssistantCopilotServer
import Synchronization

actor CallToolGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var signalCount = 0

    func signal() {
        if waiters.isEmpty {
            signalCount += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    func wait() async {
        if signalCount > 0 {
            signalCount -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

final class MockMCPBridgeService: MCPBridgeServiceProtocol, Sendable {
    private struct State {
        var tools: [MCPTool] = []
        var callResults: [String: MCPToolResult] = [:]
        var sequentialCallResults: [String: [MCPToolResult]] = [:]
        var startCallCount = 0
        var stopCallCount = 0
        var listToolsCallCount = 0
        var calledTools: [(name: String, arguments: [String: AnyCodable])] = []
        var startError: Error?
        var stopError: Error?
        var listToolsError: Error?
        var callToolError: Error?
        var callToolDelay: Duration?
    }

    private let mutex = Mutex(State())
    let callToolGate = CallToolGate()

    var tools: [MCPTool] {
        get { mutex.withLock { $0.tools } }
        set { mutex.withLock { $0.tools = newValue } }
    }

    var callResults: [String: MCPToolResult] {
        get { mutex.withLock { $0.callResults } }
        set { mutex.withLock { $0.callResults = newValue } }
    }

    var sequentialCallResults: [String: [MCPToolResult]] {
        get { mutex.withLock { $0.sequentialCallResults } }
        set { mutex.withLock { $0.sequentialCallResults = newValue } }
    }

    var startCallCount: Int { mutex.withLock { $0.startCallCount } }
    var stopCallCount: Int { mutex.withLock { $0.stopCallCount } }
    var listToolsCallCount: Int { mutex.withLock { $0.listToolsCallCount } }
    var calledTools: [(name: String, arguments: [String: AnyCodable])] { mutex.withLock { $0.calledTools } }

    var startError: Error? {
        get { mutex.withLock { $0.startError } }
        set { mutex.withLock { $0.startError = newValue } }
    }

    var stopError: Error? {
        get { mutex.withLock { $0.stopError } }
        set { mutex.withLock { $0.stopError = newValue } }
    }

    var listToolsError: Error? {
        get { mutex.withLock { $0.listToolsError } }
        set { mutex.withLock { $0.listToolsError = newValue } }
    }

    var callToolError: Error? {
        get { mutex.withLock { $0.callToolError } }
        set { mutex.withLock { $0.callToolError = newValue } }
    }

    var callToolDelay: Duration? {
        get { mutex.withLock { $0.callToolDelay } }
        set { mutex.withLock { $0.callToolDelay = newValue } }
    }

    func start() async throws {
        mutex.withLock { $0.startCallCount += 1 }
        if let error = mutex.withLock({ $0.startError }) { throw error }
    }

    func stop() async throws {
        mutex.withLock { $0.stopCallCount += 1 }
        if let error = mutex.withLock({ $0.stopError }) { throw error }
    }

    func listTools() async throws -> [MCPTool] {
        let (tools, error) = mutex.withLock {
            ($0.tools, $0.listToolsError)
        }
        mutex.withLock { $0.listToolsCallCount += 1 }
        if let error { throw error }
        return tools
    }

    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        mutex.withLock { $0.calledTools.append((name: name, arguments: arguments)) }
        await callToolGate.signal()
        if let delay = mutex.withLock({ $0.callToolDelay }) {
            try await Task.sleep(for: delay)
        }
        if let error = mutex.withLock({ $0.callToolError }) { throw error }

        return try mutex.withLock {
            if var sequence = $0.sequentialCallResults[name], !sequence.isEmpty {
                let result = sequence.removeFirst()
                $0.sequentialCallResults[name] = sequence
                return result
            }
            guard let result = $0.callResults[name] else {
                throw MCPBridgeError.toolExecutionFailed(name)
            }
            return result
        }
    }
}
