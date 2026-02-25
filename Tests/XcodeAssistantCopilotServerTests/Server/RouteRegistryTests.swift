@testable import XcodeAssistantCopilotServer
import Hummingbird
import Testing

@Test func registryStartsWithNoRoutes() {
    let router = Router(context: AppRequestContext.self)
    let registry = RouteRegistry(router: router)

    #expect(registry.routes.isEmpty)
}

@Test func registryTracksGetRoute() {
    let router = Router(context: AppRequestContext.self)
    var registry = RouteRegistry(router: router)

    registry.get("health") { _, _ in
        Response(status: .ok)
    }

    #expect(registry.routes.count == 1)
    #expect(registry.routes[0].method == "GET")
    #expect(registry.routes[0].path == "/health")
}

@Test func registryTracksPostRoute() {
    let router = Router(context: AppRequestContext.self)
    var registry = RouteRegistry(router: router)

    registry.post("v1/chat/completions") { _, _ in
        Response(status: .ok)
    }

    #expect(registry.routes.count == 1)
    #expect(registry.routes[0].method == "POST")
    #expect(registry.routes[0].path == "/v1/chat/completions")
}

@Test func registryTracksMultipleRoutes() {
    let router = Router(context: AppRequestContext.self)
    var registry = RouteRegistry(router: router)

    registry.get("health") { _, _ in Response(status: .ok) }
    registry.get("v1/models") { _, _ in Response(status: .ok) }
    registry.post("v1/chat/completions") { _, _ in Response(status: .ok) }

    #expect(registry.routes.count == 3)
}

@Test func registryPreservesRouteOrder() {
    let router = Router(context: AppRequestContext.self)
    var registry = RouteRegistry(router: router)

    registry.get("health") { _, _ in Response(status: .ok) }
    registry.get("v1/models") { _, _ in Response(status: .ok) }
    registry.post("v1/chat/completions") { _, _ in Response(status: .ok) }

    #expect(registry.routes[0].path == "/health")
    #expect(registry.routes[1].path == "/v1/models")
    #expect(registry.routes[2].path == "/v1/chat/completions")
}

@Test func registrySummaryFormatsAllRoutes() {
    let router = Router(context: AppRequestContext.self)
    var registry = RouteRegistry(router: router)

    registry.get("health") { _, _ in Response(status: .ok) }
    registry.get("v1/models") { _, _ in Response(status: .ok) }
    registry.post("v1/chat/completions") { _, _ in Response(status: .ok) }

    let summary = registry.summary()

    #expect(summary == "GET /health, GET /v1/models, POST /v1/chat/completions")
}

@Test func registrySummaryIsEmptyWhenNoRoutes() {
    let router = Router(context: AppRequestContext.self)
    let registry = RouteRegistry(router: router)

    #expect(registry.summary() == "")
}

@Test func routeDescriptorDescriptionIncludesMethodAndPath() {
    let descriptor = RouteDescriptor(method: "GET", path: "/v1/models")

    #expect(descriptor.description == "GET /v1/models")
}