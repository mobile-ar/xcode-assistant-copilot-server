@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Test func cachedModelsIfValidReturnsNilWhenEmpty() async {
    let cache = ModelFetchCache()

    let result = await cache.cachedModelsIfValid(ttl: 600)

    #expect(result == nil)
}

@Test func cachedModelsIfValidReturnModelsWhenWithinTTL() async {
    let cache = ModelFetchCache()
    let models = [CopilotModel(id: "gpt-4")]
    await cache.recordFetch(models: models)

    let result = await cache.cachedModelsIfValid(ttl: 600)

    #expect(result?.count == 1)
    #expect(result?.first?.id == "gpt-4")
}

@Test func cachedModelsIfValidReturnsNilWhenExpired() async throws {
    let cache = ModelFetchCache()
    await cache.recordFetch(models: [CopilotModel(id: "gpt-4")])

    try await Task.sleep(for: .milliseconds(20))

    let result = await cache.cachedModelsIfValid(ttl: 0.01)

    #expect(result == nil)
}

@Test func recordFetchUpdatesLastFetchTime() async {
    let cache = ModelFetchCache()

    #expect(await cache.lastFetchTime == nil)

    await cache.recordFetch(models: [])

    #expect(await cache.lastFetchTime != nil)
}

@Test func recordFetchReplacePreviouslyCachedModels() async {
    let cache = ModelFetchCache()
    await cache.recordFetch(models: [CopilotModel(id: "model-a")])
    await cache.recordFetch(models: [CopilotModel(id: "model-b")])

    let result = await cache.cachedModelsIfValid(ttl: 600)

    #expect(result?.count == 1)
    #expect(result?.first?.id == "model-b")
}
