@testable import XcodeAssistantCopilotServer
import Hummingbird

struct ServerTestHarness {
    let authService: MockAuthService
    let copilotAPI: MockCopilotAPIService
    let bridgeHolder: MCPBridgeHolder
    let configurationStore: ConfigurationStore

    init(
        authService: MockAuthService = MockAuthService(),
        copilotAPI: MockCopilotAPIService = MockCopilotAPIService(),
        bridgeHolder: MCPBridgeHolder = MCPBridgeHolder(),
        configurationStore: ConfigurationStore = ConfigurationStore(initial: ServerConfiguration())
    ) {
        self.authService = authService
        self.copilotAPI = copilotAPI
        self.bridgeHolder = bridgeHolder
        self.configurationStore = configurationStore
    }

    func makeApplication() -> some ApplicationProtocol {
        CopilotServer(
            port: 8080,
            logger: MockLogger(),
            configurationStore: configurationStore,
            authService: authService,
            copilotAPI: copilotAPI,
            bridgeHolder: bridgeHolder
        ).makeApplication()
    }
}