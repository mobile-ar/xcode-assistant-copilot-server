import Hummingbird

public struct AppRequestContext: RequestContext {
    public var coreContext: CoreRequestContextStorage

    public init(source: Source) {
        self.coreContext = .init(source: source)
    }
}