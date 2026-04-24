import Testing
import Foundation
import Darwin
@testable import XcodeAssistantCopilotServer

private let validBaseJSON = """
{
    "mcpServers": {},
    "allowedCliTools": ["git"],
    "bodyLimitMiB": 4,
    "excludedFilePatterns": [],
    "autoApprovePermissions": false,
    "reasoningEffort": "high",
    "maxAgentLoopIterations": 40,
    "timeouts": {
        "requestTimeoutSeconds": 300,
        "streamingEndpointTimeoutSeconds": 300,
        "httpClientTimeoutSeconds": 300
    }
}
"""

private let updatedAllowedCliToolsJSON = """
{
    "mcpServers": {},
    "allowedCliTools": ["git", "xcodebuild"],
    "bodyLimitMiB": 4,
    "excludedFilePatterns": [],
    "autoApprovePermissions": false,
    "reasoningEffort": "high",
    "maxAgentLoopIterations": 40,
    "timeouts": {
        "requestTimeoutSeconds": 300,
        "streamingEndpointTimeoutSeconds": 300,
        "httpClientTimeoutSeconds": 300
    }
}
"""

private let secondUpdateJSON = """
{
    "mcpServers": {},
    "allowedCliTools": ["swift"],
    "bodyLimitMiB": 4,
    "excludedFilePatterns": [],
    "autoApprovePermissions": false,
    "reasoningEffort": "high",
    "maxAgentLoopIterations": 40,
    "timeouts": {
        "requestTimeoutSeconds": 300,
        "streamingEndpointTimeoutSeconds": 300,
        "httpClientTimeoutSeconds": 300
    }
}
"""

private func makeTempFilePath(suffix: String = "json") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("watcher-test-\(UUID().uuidString).\(suffix)")
}

private func writeJSONAtomic(_ json: String, to url: URL) throws {
    try json.write(to: url, atomically: true, encoding: .utf8)
}

private func writeJSONNonAtomic(_ json: String, to url: URL) throws {
    try json.write(to: url, atomically: false, encoding: .utf8)
}

/// Simulates how nvim and other editors perform an atomic save: write to a
/// temp file in the same directory, then rename it over the target path.
/// Uses POSIX rename(2) directly so it can atomically replace an existing file,
/// which Foundation's moveItem cannot do.
private func writeJSONEditorStyle(_ json: String, to url: URL) throws {
    let dir = url.deletingLastPathComponent()
    let tmp = dir.appendingPathComponent(".watcher-test-tmp-\(UUID().uuidString).json")
    try json.write(to: tmp, atomically: false, encoding: .utf8)
    guard Darwin.rename(tmp.path, url.path) == 0 else {
        let code = errno
        try? FileManager.default.removeItem(at: tmp)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

@Test func watcherYieldsNewConfigOnNonAtomicWrite() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try writeJSONNonAtomic(updatedAllowedCliToolsJSON, to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(2))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    let config = try #require(receivedConfig)
    #expect(config.allowedCliTools == ["git", "xcodebuild"])
}

@Test func watcherYieldsNewConfigOnAtomicWriteRename() async throws {
    // Covers the nvim / vim / most editors use case: they write to a temp file
    // and rename it over the target, which produces a .delete kernel event on
    // the watched descriptor. The watcher must reopen the new inode and still
    // deliver a reload.
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try writeJSONEditorStyle(updatedAllowedCliToolsJSON, to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    let config = try #require(receivedConfig, "Watcher did not yield a config after atomic rename write")
    #expect(config.allowedCliTools == ["git", "xcodebuild"])
}

@Test func watcherYieldsNewConfigWhenFileIsRenamedAway() async throws {
    // Covers editors that rename the watched file away and then place a new
    // file at the same path (produces a .rename kernel event on the fd).
    // The watcher must reopen the new file and deliver a reload.
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))

    // Move the watched file away, then write updated content at the original path.
    let movedAway = makeTempFilePath()
    defer { try? FileManager.default.removeItem(at: movedAway) }
    guard Darwin.rename(tempFile.path, movedAway.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    try writeJSONNonAtomic(updatedAllowedCliToolsJSON, to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    let config = try #require(receivedConfig, "Watcher did not yield a config after file was renamed away")
    #expect(config.allowedCliTools == ["git", "xcodebuild"])
}

@Test func watcherContinuesToWatchAfterMultipleAtomicWrites() async throws {
    // Verifies that the watcher re-arms itself correctly after each atomic
    // rename so that a second editor-style save also triggers a reload.
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))

    let tempFilePath = tempFile.path
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        try? writeJSONEditorStyle(updatedAllowedCliToolsJSON, to: URL(fileURLWithPath: tempFilePath))
        // Wait longer than the 300 ms debounce + reopen window so the first
        // reload completes before the second write opens a new debounce window.
        try? await Task.sleep(for: .milliseconds(900))
        try? writeJSONEditorStyle(secondUpdateJSON, to: URL(fileURLWithPath: tempFilePath))
    }

    let collectedConfigs: [ServerConfiguration] = await withTaskGroup(
        of: [ServerConfiguration].self
    ) { group in
        group.addTask {
            var configs: [ServerConfiguration] = []
            var sawFirst = false
            var sawSecond = false
            for await config in stream {
                configs.append(config)
                let tools = config.allowedCliTools
                if tools == ["git", "xcodebuild"] {
                    sawFirst = true
                }
                if tools == ["swift"] {
                    sawSecond = true
                }
                if sawFirst && sawSecond {
                    return configs
                }
            }
            return configs
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return []
        }
        let result = await group.next() ?? []
        group.cancelAll()
        return result
    }

    let allowedToolsSnapshots = collectedConfigs.map(\.allowedCliTools)
    #expect(allowedToolsSnapshots.contains(["git", "xcodebuild"]), "Watcher did not emit first updated config snapshot")
    #expect(allowedToolsSnapshots.contains(["swift"]), "Watcher did not emit second updated config snapshot")
}

@Test func watcherIgnoresInvalidJSON() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try writeJSONNonAtomic("{ invalid json !!!", to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(1200))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    #expect(receivedConfig == nil)
}

@Test func watcherYieldsLatestConfigAfterMultipleNonAtomicWrites() async throws {
    // Verifies that sequential non-atomic writes each produce a yield from the
    // same open stream. Two writes are performed with enough gap between them
    // (> 300 ms debounce) so each triggers an independent reload.
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))

    let tempFilePath = tempFile.path
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        try? writeJSONNonAtomic(updatedAllowedCliToolsJSON, to: URL(fileURLWithPath: tempFilePath))
        // Wait longer than the 300 ms debounce so the first reload completes
        // before the second write opens a new debounce window.
        try? await Task.sleep(for: .milliseconds(700))
        try? writeJSONNonAtomic(secondUpdateJSON, to: URL(fileURLWithPath: tempFilePath))
    }

    let collectedConfigs: [ServerConfiguration] = await withTaskGroup(
        of: [ServerConfiguration].self
    ) { group in
        group.addTask {
            var configs: [ServerConfiguration] = []
            var sawFirst = false
            var sawSecond = false
            for await config in stream {
                configs.append(config)
                let tools = config.allowedCliTools
                if tools == ["git", "xcodebuild"] {
                    sawFirst = true
                }
                if tools == ["swift"] {
                    sawSecond = true
                }
                if sawFirst && sawSecond {
                    return configs
                }
            }
            return configs
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return []
        }
        let result = await group.next() ?? []
        group.cancelAll()
        return result
    }

    let allowedToolsSnapshots = collectedConfigs.map(\.allowedCliTools)
    #expect(allowedToolsSnapshots.contains(["git", "xcodebuild"]), "Watcher did not emit first updated config snapshot")
    #expect(allowedToolsSnapshots.contains(["swift"]), "Watcher did not emit second updated config snapshot")
}

@Test func stopFinishesStream() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()

    try await Task.sleep(for: .milliseconds(200))
    await watcher.stop()

    let completed: Bool = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {}
            return true
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(2))
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }

    #expect(completed == true)
}

@Test func watcherYieldsConfigAfterFileDeletedAndRecreated() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try FileManager.default.removeItem(at: tempFile)

    try await Task.sleep(for: .milliseconds(300))
    try writeJSONNonAtomic(updatedAllowedCliToolsJSON, to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    let config = try #require(receivedConfig, "Watcher did not yield a config after file was deleted and recreated")
    #expect(config.allowedCliTools == ["git", "xcodebuild"])
}

@Test func watcherLogsWarningWhenFileIsDeletedAndNeverRecreated() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try FileManager.default.removeItem(at: tempFile)

    try await Task.sleep(for: .milliseconds(2500))

    #expect(logger.warnMessages.contains { $0.contains("giving up watching") })

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(500))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    #expect(receivedConfig == nil)
}

@Test func watcherYieldsConfigAfterFileDeletedAndRecreatedWithDelay() async throws {
    let tempFile = makeTempFilePath()
    try writeJSONNonAtomic(validBaseJSON, to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let logger = MockLogger()
    let loader = ConfigurationLoader(logger: logger)
    let watcher = ConfigurationWatcher(path: tempFile.path, loader: loader, logger: logger)

    let stream = await watcher.changes()
    await watcher.start()
    defer { Task { await watcher.stop() } }

    try await Task.sleep(for: .milliseconds(200))
    try FileManager.default.removeItem(at: tempFile)

    try await Task.sleep(for: .milliseconds(800))
    try writeJSONNonAtomic(updatedAllowedCliToolsJSON, to: tempFile)

    let receivedConfig: ServerConfiguration? = await withTaskGroup(of: ServerConfiguration?.self) { group in
        group.addTask {
            for await config in stream {
                return config
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }

    let config = try #require(receivedConfig, "Watcher did not yield a config after delayed file recreation")
    #expect(config.allowedCliTools == ["git", "xcodebuild"])
}