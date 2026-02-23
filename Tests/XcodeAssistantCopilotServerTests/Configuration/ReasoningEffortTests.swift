import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func reasoningEffortComparableLowIsLessThanMedium() {
    #expect(ReasoningEffort.low < .medium)
}

@Test func reasoningEffortComparableMediumIsLessThanHigh() {
    #expect(ReasoningEffort.medium < .high)
}

@Test func reasoningEffortComparableHighIsLessThanXhigh() {
    #expect(ReasoningEffort.high < .xhigh)
}

@Test func reasoningEffortComparableLowIsLessThanXhigh() {
    #expect(ReasoningEffort.low < .xhigh)
}

@Test func reasoningEffortComparableEqualValuesAreNotLessThan() {
    #expect(!(ReasoningEffort.high < .high))
}

@Test func reasoningEffortComparableHigherIsNotLessThanLower() {
    #expect(!(ReasoningEffort.xhigh < .high))
    #expect(!(ReasoningEffort.high < .medium))
    #expect(!(ReasoningEffort.medium < .low))
}

@Test func reasoningEffortMinReturnsLowerValue() {
    #expect(min(.xhigh, .high) == ReasoningEffort.high)
    #expect(min(.high, .low) == ReasoningEffort.low)
    #expect(min(.medium, .xhigh) == ReasoningEffort.medium)
    #expect(min(.low, .low) == ReasoningEffort.low)
}

@Test func reasoningEffortNextLowerFromXhighIsHigh() {
    #expect(ReasoningEffort.xhigh.nextLower == .high)
}

@Test func reasoningEffortNextLowerFromHighIsMedium() {
    #expect(ReasoningEffort.high.nextLower == .medium)
}

@Test func reasoningEffortNextLowerFromMediumIsLow() {
    #expect(ReasoningEffort.medium.nextLower == .low)
}

@Test func reasoningEffortNextLowerFromLowIsNil() {
    #expect(ReasoningEffort.low.nextLower == nil)
}

@Test func reasoningEffortFullDescendingChain() {
    var current: ReasoningEffort? = .xhigh
    var chain: [ReasoningEffort] = []
    while let effort = current {
        chain.append(effort)
        current = effort.nextLower
    }
    #expect(chain == [.xhigh, .high, .medium, .low])
}

@Test func reasoningEffortSortingProducesAscendingOrder() {
    let shuffled: [ReasoningEffort] = [.high, .low, .xhigh, .medium]
    let sorted = shuffled.sorted()
    #expect(sorted == [.low, .medium, .high, .xhigh])
}