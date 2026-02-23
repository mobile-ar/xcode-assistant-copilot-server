import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func resolverReturnsConfiguredEffortWhenNoCacheExists() async {
    let resolver = ReasoningEffortResolver()
    let result = await resolver.resolve(configured: .xhigh, for: "gpt-5.1-codex")
    #expect(result == .xhigh)
}

@Test func resolverClampsToRecordedMaxEffort() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.high, for: "gpt-5.1-codex")
    let result = await resolver.resolve(configured: .xhigh, for: "gpt-5.1-codex")
    #expect(result == .high)
}

@Test func resolverReturnsConfiguredWhenLowerThanCachedMax() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.high, for: "gpt-5.1-codex")
    let result = await resolver.resolve(configured: .medium, for: "gpt-5.1-codex")
    #expect(result == .medium)
}

@Test func resolverReturnsConfiguredWhenEqualToCachedMax() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.high, for: "gpt-5.1-codex")
    let result = await resolver.resolve(configured: .high, for: "gpt-5.1-codex")
    #expect(result == .high)
}

@Test func resolverCachesPerModel() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.high, for: "gpt-5.1-codex")
    await resolver.recordMaxEffort(.medium, for: "some-other-model")

    let result1 = await resolver.resolve(configured: .xhigh, for: "gpt-5.1-codex")
    #expect(result1 == .high)

    let result2 = await resolver.resolve(configured: .xhigh, for: "some-other-model")
    #expect(result2 == .medium)
}

@Test func resolverDoesNotAffectUncachedModels() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.medium, for: "gpt-5.1-codex")
    let result = await resolver.resolve(configured: .xhigh, for: "o3-mini")
    #expect(result == .xhigh)
}

@Test func resolverUpdatesMaxEffortWhenRecordedAgain() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.high, for: "gpt-5.1-codex")
    let first = await resolver.resolve(configured: .xhigh, for: "gpt-5.1-codex")
    #expect(first == .high)

    await resolver.recordMaxEffort(.medium, for: "gpt-5.1-codex")
    let second = await resolver.resolve(configured: .xhigh, for: "gpt-5.1-codex")
    #expect(second == .medium)
}

@Test func resolverClampsLowToLow() async {
    let resolver = ReasoningEffortResolver()
    await resolver.recordMaxEffort(.low, for: "restricted-model")
    let result = await resolver.resolve(configured: .xhigh, for: "restricted-model")
    #expect(result == .low)
}

@Test func resolverHandlesAllEffortLevelsAsMax() async {
    let efforts: [ReasoningEffort] = [.low, .medium, .high, .xhigh]
    for maxEffort in efforts {
        let resolver = ReasoningEffortResolver()
        await resolver.recordMaxEffort(maxEffort, for: "test-model")
        let result = await resolver.resolve(configured: .xhigh, for: "test-model")
        #expect(result == maxEffort)
    }
}