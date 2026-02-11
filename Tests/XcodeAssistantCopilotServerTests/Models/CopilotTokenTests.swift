import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func copilotTokenDefaultAPIEndpoint() {
    let token = CopilotToken(token: "test-token", expiresAt: Date.now.addingTimeInterval(3600))
    #expect(token.apiEndpoint == "https://api.individual.githubcopilot.com")
}

@Test func copilotTokenCustomAPIEndpoint() {
    let token = CopilotToken(
        token: "test-token",
        expiresAt: Date.now.addingTimeInterval(3600),
        apiEndpoint: "https://api.business.githubcopilot.com"
    )
    #expect(token.apiEndpoint == "https://api.business.githubcopilot.com")
}

@Test func copilotTokenIsValidWhenNotExpired() {
    let token = CopilotToken(
        token: "test-token",
        expiresAt: Date.now.addingTimeInterval(3600),
        apiEndpoint: "https://api.individual.githubcopilot.com"
    )
    #expect(token.isValid)
    #expect(!token.isExpired)
    #expect(!token.isExpiringSoon)
}

@Test func copilotTokenIsExpiredWhenPastExpiry() {
    let token = CopilotToken(
        token: "test-token",
        expiresAt: Date.now.addingTimeInterval(-60),
        apiEndpoint: "https://api.individual.githubcopilot.com"
    )
    #expect(token.isExpired)
    #expect(!token.isValid)
}

@Test func copilotTokenIsExpiringSoonWithinFiveMinutes() {
    let token = CopilotToken(
        token: "test-token",
        expiresAt: Date.now.addingTimeInterval(200),
        apiEndpoint: "https://api.individual.githubcopilot.com"
    )
    #expect(!token.isExpired)
    #expect(token.isExpiringSoon)
    #expect(!token.isValid)
}

@Test func copilotTokenResponseParsesEndpointFromJSON() throws {
    let json = """
    {
        "token": "jwt-copilot-token",
        "expires_at": 1700000000,
        "endpoints": {
            "api": "https://api.business.githubcopilot.com"
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.token == "jwt-copilot-token")
    #expect(copilotToken.apiEndpoint == "https://api.business.githubcopilot.com")
    #expect(copilotToken.expiresAt == Date(timeIntervalSince1970: 1700000000))
}

@Test func copilotTokenResponseDefaultsEndpointWhenMissing() throws {
    let json = """
    {
        "token": "jwt-copilot-token",
        "expires_at": 1700000000
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.token == "jwt-copilot-token")
    #expect(copilotToken.apiEndpoint == "https://api.individual.githubcopilot.com")
}

@Test func copilotTokenResponseDefaultsEndpointWhenAPIFieldIsNull() throws {
    let json = """
    {
        "token": "jwt-copilot-token",
        "expires_at": 1700000000,
        "endpoints": {}
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.apiEndpoint == "https://api.individual.githubcopilot.com")
}

@Test func copilotTokenResponseParsesIndividualEndpoint() throws {
    let json = """
    {
        "token": "jwt-individual",
        "expires_at": 1700000000,
        "endpoints": {
            "api": "https://api.individual.githubcopilot.com"
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.apiEndpoint == "https://api.individual.githubcopilot.com")
}

@Test func copilotTokenResponseParsesEnterpriseEndpoint() throws {
    let json = """
    {
        "token": "jwt-enterprise",
        "expires_at": 1700000000,
        "endpoints": {
            "api": "https://api.enterprise.githubcopilot.com"
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.apiEndpoint == "https://api.enterprise.githubcopilot.com")
}

@Test func copilotTokenEndpointsDecodesAPIField() throws {
    let json = """
    {
        "api": "https://custom.endpoint.com"
    }
    """.data(using: .utf8)!

    let endpoints = try JSONDecoder().decode(CopilotTokenEndpoints.self, from: json)
    #expect(endpoints.api == "https://custom.endpoint.com")
}

@Test func copilotTokenEndpointsDecodesEmptyObject() throws {
    let json = """
    {}
    """.data(using: .utf8)!

    let endpoints = try JSONDecoder().decode(CopilotTokenEndpoints.self, from: json)
    #expect(endpoints.api == nil)
}

@Test func copilotCredentialsStoresTokenAndEndpoint() {
    let credentials = CopilotCredentials(
        token: "bearer-token",
        apiEndpoint: "https://api.business.githubcopilot.com"
    )
    #expect(credentials.token == "bearer-token")
    #expect(credentials.apiEndpoint == "https://api.business.githubcopilot.com")
}

@Test func copilotCredentialsIsSendable() {
    let credentials = CopilotCredentials(
        token: "test-token",
        apiEndpoint: "https://api.individual.githubcopilot.com"
    )
    let task = Task { credentials }
    _ = task
}

@Test func copilotTokenResponseWithFullPayload() throws {
    let json = """
    {
        "token": "jwt-full-payload",
        "expires_at": 1800000000,
        "endpoints": {
            "api": "https://api.individual.githubcopilot.com"
        },
        "chat_enabled": true,
        "individual": true,
        "sku": "copilot_individual_subscriber"
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.token == "jwt-full-payload")
    #expect(copilotToken.apiEndpoint == "https://api.individual.githubcopilot.com")
    #expect(copilotToken.expiresAt == Date(timeIntervalSince1970: 1800000000))
}

@Test func copilotTokenResponseEndpointsWithExtraFields() throws {
    let json = """
    {
        "token": "jwt-extra-endpoints",
        "expires_at": 1700000000,
        "endpoints": {
            "api": "https://api.business.githubcopilot.com",
            "origin-tracker": "https://origin-tracker.githubcopilot.com",
            "proxy": "https://proxy.githubcopilot.com",
            "telemetry": "https://telemetry.githubcopilot.com"
        }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(CopilotTokenResponse.self, from: json)
    let copilotToken = response.toCopilotToken()

    #expect(copilotToken.apiEndpoint == "https://api.business.githubcopilot.com")
}