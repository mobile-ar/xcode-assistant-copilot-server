struct CoreServices: Sendable {
    let processRunner: ProcessRunnerProtocol
    let httpClient: HTTPClientProtocol
    let requestHeaders: CopilotRequestHeadersProtocol
    let authService: AuthServiceProtocol
    let deviceFlowService: DeviceFlowServiceProtocol
    let copilotAPI: CopilotAPIServiceProtocol
}