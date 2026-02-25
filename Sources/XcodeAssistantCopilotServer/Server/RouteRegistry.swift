import Hummingbird
import HTTPTypes
import Synchronization

public struct RouteDescriptor: Sendable {
    public let method: String
    public let path: String

    public var description: String {
        "\(method) \(path)"
    }
}

public struct RouteRegistry {
    private let router: Router<AppRequestContext>
    private var registeredRoutes: [RouteDescriptor] = []

    public var routes: [RouteDescriptor] {
        registeredRoutes
    }

    public init(router: Router<AppRequestContext>) {
        self.router = router
    }

    @discardableResult
    public mutating func get(
        _ path: RouterPath,
        handler: @Sendable @escaping (Request, AppRequestContext) async throws -> Response
    ) -> Self {
        router.get(path) { request, context in
            try await handler(request, context)
        }
        registeredRoutes.append(RouteDescriptor(method: "GET", path: path.description))
        return self
    }

    @discardableResult
    public mutating func post(
        _ path: RouterPath,
        handler: @Sendable @escaping (Request, AppRequestContext) async throws -> Response
    ) -> Self {
        router.post(path) { request, context in
            try await handler(request, context)
        }
        registeredRoutes.append(RouteDescriptor(method: "POST", path: path.description))
        return self
    }

    public func summary() -> String {
        registeredRoutes.map(\.description).joined(separator: ", ")
    }
}