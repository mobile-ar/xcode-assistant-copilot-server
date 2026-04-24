import Foundation
import Hummingbird

public struct AppRequestContext: RequestContext {
    public var coreContext: CoreRequestContextStorage
    public let requestID: String

    public init(source: Source) {
        self.coreContext = .init(source: source)
        self.requestID = UUID().uuidString
    }
}