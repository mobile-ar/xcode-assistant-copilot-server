import Foundation

public enum MCPBridgeError: Error, CustomStringConvertible {
    case notStarted
    case alreadyStarted
    case processSpawnFailed(String)
    case initializationFailed(String)
    case communicationFailed(String)
    case toolExecutionFailed(String)
    case mcpBridgeNotFound

    public var description: String {
        switch self {
        case .notStarted:
            "MCP bridge has not been started"
        case .alreadyStarted:
            "MCP bridge is already running"
        case .processSpawnFailed(let message):
            "Failed to spawn mcpbridge process: \(message)"
        case .initializationFailed(let message):
            "MCP bridge initialization failed: \(message)"
        case .communicationFailed(let message):
            "MCP bridge communication failed: \(message)"
        case .toolExecutionFailed(let message):
            "MCP bridge tool execution failed: \(message)"
        case .mcpBridgeNotFound:
            "xcrun mcpbridge not found. This requires Xcode 26.3 or later."
        }
    }
}

public protocol MCPBridgeServiceProtocol: Sendable {
    func start() async throws
    func stop() async throws
    func listTools() async throws -> [MCPTool]
    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult
}

public actor MCPBridgeService: MCPBridgeServiceProtocol {
    private let serverConfig: MCPServerConfiguration
    private let logger: LoggerProtocol
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var cachedTools: [MCPTool]?
    private var readTask: Task<Void, Never>?
    private var lineBuffer: String = ""

    public init(serverConfig: MCPServerConfiguration, logger: LoggerProtocol) {
        self.serverConfig = serverConfig
        self.logger = logger
    }

    public func start() async throws {
        guard process == nil else {
            throw MCPBridgeError.alreadyStarted
        }

        let command: String
        let arguments: [String]

        if let configCommand = serverConfig.command {
            command = configCommand
            arguments = serverConfig.args ?? []
        } else {
            command = "/usr/bin/xcrun"
            arguments = ["mcpbridge"]
        }

        try await verifyMCPBridgeExists(command: command, arguments: arguments)

        let newProcess = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: resolveCommandPath(command))
        newProcess.arguments = arguments
        newProcess.standardInput = stdin
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        if let configEnv = serverConfig.env {
            for (key, value) in configEnv {
                env[key] = value
            }
        }
        newProcess.environment = env

        if let cwd = serverConfig.cwd {
            newProcess.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        stdinPipe = stdin
        stdoutPipe = stdout
        process = newProcess

        startReadingStdout(from: stdout)
        startReadingStderr(from: stderr)

        do {
            try newProcess.run()
        } catch {
            cleanup()
            throw MCPBridgeError.processSpawnFailed(error.localizedDescription)
        }

        logger.info("MCP bridge process started (PID: \(newProcess.processIdentifier))")

        try await initialize()
    }

    public func stop() async throws {
        readTask?.cancel()
        readTask = nil

        for (id, continuation) in pendingRequests {
            continuation.resume(throwing: MCPBridgeError.communicationFailed("Bridge is stopping"))
            pendingRequests.removeValue(forKey: id)
        }

        if let process, process.isRunning {
            process.terminate()
            logger.info("MCP bridge process terminated")
        }

        cleanup()
    }

    public func listTools() async throws -> [MCPTool] {
        if let cached = cachedTools {
            return cached
        }

        guard process != nil else {
            throw MCPBridgeError.notStarted
        }

        let response = try await sendRequest(method: "tools/list")

        guard let tools = response.result?.tools else {
            logger.warn("MCP bridge returned no tools")
            cachedTools = []
            return []
        }

        let mcpTools = tools.map { MCPTool(from: $0) }
        cachedTools = mcpTools
        logger.info("Discovered \(mcpTools.count) MCP tool(s)")
        for tool in mcpTools {
            logger.debug("  - \(tool.name): \(tool.description ?? "no description")")
        }
        return mcpTools
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        guard process != nil else {
            throw MCPBridgeError.notStarted
        }

        logger.debug("Calling MCP tool: \(name)")

        let params: [String: AnyCodable] = [
            "name": AnyCodable(.string(name)),
            "arguments": AnyCodable(.dictionary(arguments)),
        ]

        let response = try await sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            throw MCPBridgeError.toolExecutionFailed("\(error.message) (code: \(error.code))")
        }

        guard let result = response.result else {
            return MCPToolResult(content: [], isError: false)
        }

        let content = (result.content ?? []).map { mcpContent in
            MCPToolResultContent(type: mcpContent.type, text: mcpContent.text)
        }

        let toolResult = MCPToolResult(content: content, isError: false)
        logger.debug("MCP tool \(name) completed: \(toolResult.textContent.prefix(200))")
        return toolResult
    }

    private func initialize() async throws {
        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable(.string("2024-11-05")),
            "capabilities": AnyCodable(.dictionary([:])),
            "clientInfo": AnyCodable(.dictionary([
                "name": AnyCodable(.string("xcode-assistant-copilot-server")),
                "version": AnyCodable(.string("1.0.0")),
            ])),
        ]

        let response = try await sendRequest(method: "initialize", params: params)

        if let error = response.error {
            throw MCPBridgeError.initializationFailed(error.message)
        }

        logger.info("MCP bridge initialized successfully")

        try await sendNotification(method: "notifications/initialized")
    }

    private func sendRequest(
        method: String,
        params: [String: AnyCodable]? = nil
    ) async throws -> MCPResponse {
        guard stdinPipe != nil else {
            throw MCPBridgeError.notStarted
        }

        let requestId = nextRequestId
        nextRequestId += 1

        let request = MCPRequest(id: requestId, method: method, params: params)

        let data: Data
        do {
            data = try JSONEncoder().encode(request)
        } catch {
            throw MCPBridgeError.communicationFailed("Failed to encode request: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            guard var messageData = String(data: data, encoding: .utf8) else {
                pendingRequests.removeValue(forKey: requestId)
                continuation.resume(throwing: MCPBridgeError.communicationFailed("Failed to create message string"))
                return
            }

            messageData += "\n"

            guard let writeData = messageData.data(using: .utf8) else {
                pendingRequests.removeValue(forKey: requestId)
                continuation.resume(throwing: MCPBridgeError.communicationFailed("Failed to encode message"))
                return
            }

            stdinPipe?.fileHandleForWriting.write(writeData)
            logger.debug("Sent MCP request #\(requestId): \(method)")
        }
    }

    private func sendNotification(
        method: String,
        params: [String: AnyCodable]? = nil
    ) async throws {
        guard stdinPipe != nil else {
            throw MCPBridgeError.notStarted
        }

        let notification = MCPNotification(method: method, params: params)

        let data: Data
        do {
            data = try JSONEncoder().encode(notification)
        } catch {
            throw MCPBridgeError.communicationFailed(
                "Failed to encode notification: \(error.localizedDescription)"
            )
        }

        guard var messageString = String(data: data, encoding: .utf8) else {
            throw MCPBridgeError.communicationFailed("Failed to create notification string")
        }

        messageString += "\n"

        guard let writeData = messageString.data(using: .utf8) else {
            throw MCPBridgeError.communicationFailed("Failed to encode notification")
        }

        stdinPipe?.fileHandleForWriting.write(writeData)
        logger.debug("Sent MCP notification: \(method)")
    }

    private func startReadingStdout(from pipe: Pipe) {
        let fileHandle = pipe.fileHandleForReading

        readTask = Task { [weak self] in
            while !Task.isCancelled {
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    break
                }

                guard let text = String(data: data, encoding: .utf8) else {
                    continue
                }

                await self?.processIncomingText(text)
            }
        }
    }

    private func startReadingStderr(from pipe: Pipe) {
        let fileHandle = pipe.fileHandleForReading

        Task { [logger] in
            while true {
                let data = fileHandle.availableData
                guard !data.isEmpty else { break }

                if let text = String(data: data, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        logger.debug("MCP bridge stderr: \(trimmed)")
                    }
                }
            }
        }
    }

    private func processIncomingText(_ text: String) {
        lineBuffer += text

        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            processLine(trimmed)
        }
    }

    private func processLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            logger.warn("MCP bridge: failed to convert line to data")
            return
        }

        do {
            let response = try MCPResponseParser.parse(from: data)

            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                logger.debug("Received MCP response for request #\(id)")
                continuation.resume(returning: response)
            } else {
                logger.debug("Received MCP notification or unmatched response")
            }
        } catch {
            logger.warn("MCP bridge: failed to parse response: \(error)")
        }
    }

    private func verifyMCPBridgeExists(command: String, arguments: [String]) async throws {
        if command == "/usr/bin/xcrun" || command == "xcrun" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["--find", "mcpbridge"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw MCPBridgeError.mcpBridgeNotFound
            }

            guard process.terminationStatus == 0 else {
                throw MCPBridgeError.mcpBridgeNotFound
            }

            logger.debug("Found mcpbridge via xcrun")
        }
    }

    private func resolveCommandPath(_ command: String) -> String {
        if command.hasPrefix("/") {
            return command
        }

        let knownPaths = [
            "/usr/bin/",
            "/usr/local/bin/",
            "/opt/homebrew/bin/",
        ]

        for prefix in knownPaths {
            let fullPath = prefix + command
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        return "/usr/bin/env"
    }

    private func cleanup() {
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        cachedTools = nil
        lineBuffer = ""
    }
}