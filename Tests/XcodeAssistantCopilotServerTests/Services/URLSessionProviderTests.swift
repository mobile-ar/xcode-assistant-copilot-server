import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func configuredSessionUsesDefaultValues() {
    let session = URLSessionProvider.configuredSession()
    let config = session.configuration

    #expect(config.timeoutIntervalForRequest == 300)
    #expect(config.waitsForConnectivity == true)
    #expect(config.httpMaximumConnectionsPerHost == 6)
}

@Test func configuredSessionUsesCustomTimeout() {
    let session = URLSessionProvider.configuredSession(timeoutIntervalForRequest: 60)
    let config = session.configuration

    #expect(config.timeoutIntervalForRequest == 60)
    #expect(config.waitsForConnectivity == true)
    #expect(config.httpMaximumConnectionsPerHost == 6)
}

@Test func configuredSessionUsesCustomWaitsForConnectivity() {
    let session = URLSessionProvider.configuredSession(waitsForConnectivity: false)
    let config = session.configuration

    #expect(config.timeoutIntervalForRequest == 300)
    #expect(config.waitsForConnectivity == false)
    #expect(config.httpMaximumConnectionsPerHost == 6)
}

@Test func configuredSessionUsesCustomMaxConnections() {
    let session = URLSessionProvider.configuredSession(httpMaximumConnectionsPerHost: 2)
    let config = session.configuration

    #expect(config.timeoutIntervalForRequest == 300)
    #expect(config.waitsForConnectivity == true)
    #expect(config.httpMaximumConnectionsPerHost == 2)
}

@Test func configuredSessionUsesAllCustomValues() {
    let session = URLSessionProvider.configuredSession(
        timeoutIntervalForRequest: 120,
        waitsForConnectivity: false,
        httpMaximumConnectionsPerHost: 10
    )
    let config = session.configuration

    #expect(config.timeoutIntervalForRequest == 120)
    #expect(config.waitsForConnectivity == false)
    #expect(config.httpMaximumConnectionsPerHost == 10)
}

@Test func configuredSessionCreatesDistinctInstances() {
    let session1 = URLSessionProvider.configuredSession()
    let session2 = URLSessionProvider.configuredSession()

    #expect(session1 !== session2)
}