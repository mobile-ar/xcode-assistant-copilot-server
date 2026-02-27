@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Test func loadStoredTokenReturnsNilWhenFileDoesNotExist() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    let path = "\(tempDir)/nonexistent-token.json"
    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: path)

    let token = try service.loadStoredToken()
    #expect(token == nil)
}

@Test func loadStoredTokenReturnsTokenWhenFileExists() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_test123","token_type":"bearer","scope":"user:email"}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    let token = try service.loadStoredToken()
    #expect(token?.accessToken == "gho_test123")
    #expect(token?.tokenType == "bearer")
    #expect(token?.scope == "user:email")
}

@Test func loadStoredTokenThrowsWhenFileIsInvalidJSON() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    try "not valid json".data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    #expect(throws: (any Error).self) {
        _ = try service.loadStoredToken()
    }
}

@Test func deleteStoredTokenRemovesFile() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_delete_me","token_type":"bearer","scope":""}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))
    #expect(FileManager.default.fileExists(atPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    try service.deleteStoredToken()
    #expect(!FileManager.default.fileExists(atPath: tokenPath))
}

@Test func deleteStoredTokenSucceedsWhenFileDoesNotExist() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    let path = "\(tempDir)/nonexistent.json"
    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: path)

    try service.deleteStoredToken()
}

@Test func loadStoredTokenAfterDeleteReturnsNil() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_round_trip","token_type":"bearer","scope":"user:email"}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    let loaded = try service.loadStoredToken()
    #expect(loaded?.accessToken == "gho_round_trip")

    try service.deleteStoredToken()

    let afterDelete = try service.loadStoredToken()
    #expect(afterDelete == nil)
}

@Test func deviceCodePollResponseToOAuthTokenReturnsTokenWhenValid() {
    let poll = DeviceCodePollResponse(
        accessToken: "gho_valid",
        tokenType: "bearer",
        scope: "user:email",
        error: nil,
        errorDescription: nil
    )
    let token = poll.toOAuthToken()
    #expect(token?.accessToken == "gho_valid")
    #expect(token?.tokenType == "bearer")
    #expect(token?.scope == "user:email")
}

@Test func deviceCodePollResponseToOAuthTokenReturnsNilWhenAccessTokenMissing() {
    let poll = DeviceCodePollResponse(
        accessToken: nil,
        tokenType: "bearer",
        scope: "user:email",
        error: nil,
        errorDescription: nil
    )
    #expect(poll.toOAuthToken() == nil)
}

@Test func deviceCodePollResponseToOAuthTokenReturnsNilWhenTokenTypeMissing() {
    let poll = DeviceCodePollResponse(
        accessToken: "gho_valid",
        tokenType: nil,
        scope: "user:email",
        error: nil,
        errorDescription: nil
    )
    #expect(poll.toOAuthToken() == nil)
}

@Test func deviceCodePollResponseToOAuthTokenReturnsNilWhenBothMissing() {
    let poll = DeviceCodePollResponse(
        accessToken: nil,
        tokenType: nil,
        scope: nil,
        error: "authorization_pending",
        errorDescription: "Waiting for authorization"
    )
    #expect(poll.toOAuthToken() == nil)
}

@Test func deviceCodePollResponseToOAuthTokenUsesEmptyScopeWhenNil() {
    let poll = DeviceCodePollResponse(
        accessToken: "gho_no_scope",
        tokenType: "bearer",
        scope: nil,
        error: nil,
        errorDescription: nil
    )
    let token = poll.toOAuthToken()
    #expect(token?.accessToken == "gho_no_scope")
    #expect(token?.scope == "")
}

@Test func deviceCodePollResponseDecodesFromJSON() throws {
    let json = """
    {
        "access_token": "gho_decoded",
        "token_type": "bearer",
        "scope": "user:email"
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodePollResponse.self, from: Data(json.utf8))
    #expect(decoded.accessToken == "gho_decoded")
    #expect(decoded.tokenType == "bearer")
    #expect(decoded.scope == "user:email")
    #expect(decoded.error == nil)
    #expect(decoded.errorDescription == nil)
}

@Test func deviceCodePollResponseDecodesErrorFromJSON() throws {
    let json = """
    {
        "error": "authorization_pending",
        "error_description": "The authorization request is still pending."
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodePollResponse.self, from: Data(json.utf8))
    #expect(decoded.accessToken == nil)
    #expect(decoded.tokenType == nil)
    #expect(decoded.error == "authorization_pending")
    #expect(decoded.errorDescription == "The authorization request is still pending.")
    #expect(decoded.toOAuthToken() == nil)
}

@Test func deviceCodeResponseDecodesFromJSON() throws {
    let json = """
    {
        "device_code": "dc_abc123",
        "user_code": "ABCD-1234",
        "verification_uri": "https://github.com/login/device",
        "expires_in": 900,
        "interval": 5
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodeResponse.self, from: Data(json.utf8))
    #expect(decoded.deviceCode == "dc_abc123")
    #expect(decoded.userCode == "ABCD-1234")
    #expect(decoded.verificationUri == "https://github.com/login/device")
    #expect(decoded.expiresIn == 900)
    #expect(decoded.interval == 5)
}

@Test func oauthTokenEncodesAndDecodesRoundTrip() throws {
    let original = OAuthToken(accessToken: "gho_round", tokenType: "bearer", scope: "user:email")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)
    #expect(decoded.accessToken == original.accessToken)
    #expect(decoded.tokenType == original.tokenType)
    #expect(decoded.scope == original.scope)
}

@Test func oauthTokenDefaultValues() {
    let token = OAuthToken(accessToken: "gho_defaults")
    #expect(token.accessToken == "gho_defaults")
    #expect(token.tokenType == "bearer")
    #expect(token.scope == "")
}

@Test func oauthTokenUsesSnakeCaseCodingKeys() throws {
    let token = OAuthToken(accessToken: "gho_keys", tokenType: "bearer", scope: "user")
    let data = try JSONEncoder().encode(token)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["access_token"] as? String == "gho_keys")
    #expect(json?["token_type"] as? String == "bearer")
    #expect(json?["scope"] as? String == "user")
    #expect(json?["accessToken"] == nil)
    #expect(json?["tokenType"] == nil)
}

@Test func deviceFlowErrorDescriptionsAreMeaningful() {
    let errors: [(DeviceFlowError, String)] = [
        (.requestFailed("HTTP 500"), "HTTP 500"),
        (.expired, "expired"),
        (.accessDenied, "denied"),
        (.networkError("timeout"), "timeout"),
        (.invalidResponse("bad json"), "bad json"),
        (.tokenStorageFailed("permission denied"), "permission denied"),
    ]

    for (error, expectedSubstring) in errors {
        #expect(error.description.contains(expectedSubstring))
    }
}

@Test func clientIDIsExpectedValue() {
    #expect(GitHubDeviceFlowService.clientID == "Iv1.b507a08c87ecfe98")
}

@Test func loadStoredTokenLogsDebugMessageWhenFileNotFound() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    let path = "\(tempDir)/missing-token.json"
    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: path)

    _ = try service.loadStoredToken()
    #expect(logger.debugMessages.contains { $0.contains("No stored OAuth token") })
}

@Test func loadStoredTokenLogsDebugMessageWhenTokenLoaded() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_log_test","token_type":"bearer","scope":""}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    _ = try service.loadStoredToken()
    #expect(logger.debugMessages.contains { $0.contains("Loaded stored OAuth token") })
}

@Test func deleteStoredTokenLogsDebugMessage() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_log_delete","token_type":"bearer","scope":""}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    try service.deleteStoredToken()
    #expect(logger.debugMessages.contains { $0.contains("Deleted stored OAuth token") })
}

@Test func loadStoredTokenHandlesMissingFieldsGracefully() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tokenPath = tempDir.appendingPathComponent("token.json").path
    let tokenJSON = """
    {"access_token":"gho_partial"}
    """
    try tokenJSON.data(using: .utf8)!.write(to: URL(fileURLWithPath: tokenPath))

    let logger = MockLogger()
    let httpClient = MockHTTPClient()
    let service = GitHubDeviceFlowService(logger: logger, httpClient: httpClient, tokenStoragePath: tokenPath)

    #expect(throws: (any Error).self) {
        _ = try service.loadStoredToken()
    }
}

@Test func deviceCodePollResponseDecodesWithAllFields() throws {
    let json = """
    {
        "access_token": "gho_full",
        "token_type": "bearer",
        "scope": "user:email",
        "error": null,
        "error_description": null
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodePollResponse.self, from: Data(json.utf8))
    #expect(decoded.accessToken == "gho_full")
    #expect(decoded.error == nil)
    let token = decoded.toOAuthToken()
    #expect(token?.accessToken == "gho_full")
}

@Test func deviceCodePollResponseDecodesExpiredError() throws {
    let json = """
    {
        "error": "expired_token",
        "error_description": "The device code has expired."
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodePollResponse.self, from: Data(json.utf8))
    #expect(decoded.error == "expired_token")
    #expect(decoded.errorDescription == "The device code has expired.")
    #expect(decoded.toOAuthToken() == nil)
}

@Test func deviceCodePollResponseDecodesAccessDeniedError() throws {
    let json = """
    {
        "error": "access_denied",
        "error_description": "The user has denied access."
    }
    """
    let decoded = try JSONDecoder().decode(DeviceCodePollResponse.self, from: Data(json.utf8))
    #expect(decoded.error == "access_denied")
    #expect(decoded.toOAuthToken() == nil)
}