@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Test func defaultModelsCacheTTLIs600Seconds() {
    let config = ServerConfiguration()
    #expect(config.modelsCacheTTLSeconds == 600)
}

@Test func modelsCacheTTLCanBeCustomized() {
    let config = ServerConfiguration(modelsCacheTTLSeconds: 120)
    #expect(config.modelsCacheTTLSeconds == 120)
}

@Test func modelsCacheTTLDecodesFromJSON() throws {
    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": false,
        "modelsCacheTTLSeconds": 300
    }
    """
    let data = json.data(using: .utf8)!
    let config = try JSONDecoder().decode(ServerConfiguration.self, from: data)
    #expect(config.modelsCacheTTLSeconds == 300)
}

@Test func modelsCacheTTLDefaultsTo600WhenMissingFromJSON() throws {
    let json = """
    {
        "mcpServers": {},
        "allowedCliTools": [],
        "bodyLimitMiB": 4,
        "excludedFilePatterns": [],
        "autoApprovePermissions": false
    }
    """
    let data = json.data(using: .utf8)!
    let config = try JSONDecoder().decode(ServerConfiguration.self, from: data)
    #expect(config.modelsCacheTTLSeconds == 600)
}
