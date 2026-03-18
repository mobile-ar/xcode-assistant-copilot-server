import Foundation

public actor MCPBridgeHolder {
    public private(set) var bridge: MCPBridgeServiceProtocol?

    public init(_ bridge: MCPBridgeServiceProtocol? = nil) {
        self.bridge = bridge
    }

    public func setBridge(_ bridge: MCPBridgeServiceProtocol?) {
        self.bridge = bridge
    }
}
