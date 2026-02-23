import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func fromAnyWithString() {
    let result = AnyCodable(fromAny: "hello" as Any)
    guard case .string(let value) = result.value else {
        Issue.record("Expected .string, got \(result.value)")
        return
    }
    #expect(value == "hello")
}

@Test func fromAnyWithEmptyString() {
    let result = AnyCodable(fromAny: "" as Any)
    guard case .string(let value) = result.value else {
        Issue.record("Expected .string, got \(result.value)")
        return
    }
    #expect(value == "")
}

@Test func fromAnyWithInt() {
    let result = AnyCodable(fromAny: 42 as Any)
    guard case .int(let value) = result.value else {
        Issue.record("Expected .int, got \(result.value)")
        return
    }
    #expect(value == 42)
}

@Test func fromAnyWithZeroInt() {
    let result = AnyCodable(fromAny: 0 as Any)
    guard case .int(let value) = result.value else {
        Issue.record("Expected .int, got \(result.value)")
        return
    }
    #expect(value == 0)
}

@Test func fromAnyWithNegativeInt() {
    let result = AnyCodable(fromAny: -7 as Any)
    guard case .int(let value) = result.value else {
        Issue.record("Expected .int, got \(result.value)")
        return
    }
    #expect(value == -7)
}

@Test func fromAnyWithDouble() {
    let result = AnyCodable(fromAny: 3.14 as Any)
    guard case .double(let value) = result.value else {
        Issue.record("Expected .double, got \(result.value)")
        return
    }
    #expect(value == 3.14)
}

@Test func fromAnyWithBoolTrue() {
    let result = AnyCodable(fromAny: true as Any)
    guard case .bool(let value) = result.value else {
        Issue.record("Expected .bool, got \(result.value)")
        return
    }
    #expect(value == true)
}

@Test func fromAnyWithBoolFalse() {
    let result = AnyCodable(fromAny: false as Any)
    guard case .bool(let value) = result.value else {
        Issue.record("Expected .bool, got \(result.value)")
        return
    }
    #expect(value == false)
}

@Test func fromAnyWithStringArray() {
    let result = AnyCodable(fromAny: ["a", "b", "c"] as Any)
    guard case .array(let value) = result.value else {
        Issue.record("Expected .array, got \(result.value)")
        return
    }
    #expect(value.count == 3)
    guard case .string(let first) = value[0].value else {
        Issue.record("Expected .string for first element")
        return
    }
    #expect(first == "a")
}

@Test func fromAnyWithEmptyArray() {
    let result = AnyCodable(fromAny: [Any]() as Any)
    guard case .array(let value) = result.value else {
        Issue.record("Expected .array, got \(result.value)")
        return
    }
    #expect(value.isEmpty)
}

@Test func fromAnyWithMixedArray() {
    let input: [Any] = ["text", 42, true]
    let result = AnyCodable(fromAny: input as Any)
    guard case .array(let value) = result.value else {
        Issue.record("Expected .array, got \(result.value)")
        return
    }
    #expect(value.count == 3)

    guard case .string(let s) = value[0].value else {
        Issue.record("Expected .string at index 0")
        return
    }
    #expect(s == "text")

    guard case .int(let i) = value[1].value else {
        Issue.record("Expected .int at index 1")
        return
    }
    #expect(i == 42)

    guard case .bool(let b) = value[2].value else {
        Issue.record("Expected .bool at index 2")
        return
    }
    #expect(b == true)
}

@Test func fromAnyWithDictionary() {
    let input: [String: Any] = ["name": "swift", "version": 6]
    let result = AnyCodable(fromAny: input as Any)
    guard case .dictionary(let value) = result.value else {
        Issue.record("Expected .dictionary, got \(result.value)")
        return
    }
    #expect(value.count == 2)

    guard case .string(let name) = value["name"]?.value else {
        Issue.record("Expected .string for 'name'")
        return
    }
    #expect(name == "swift")

    guard case .int(let version) = value["version"]?.value else {
        Issue.record("Expected .int for 'version'")
        return
    }
    #expect(version == 6)
}

@Test func fromAnyWithEmptyDictionary() {
    let result = AnyCodable(fromAny: [String: Any]() as Any)
    guard case .dictionary(let value) = result.value else {
        Issue.record("Expected .dictionary, got \(result.value)")
        return
    }
    #expect(value.isEmpty)
}

@Test func fromAnyWithNestedDictionary() {
    let input: [String: Any] = [
        "outer": ["inner": "value"] as [String: Any]
    ]
    let result = AnyCodable(fromAny: input as Any)
    guard case .dictionary(let outer) = result.value else {
        Issue.record("Expected .dictionary, got \(result.value)")
        return
    }

    guard case .dictionary(let inner) = outer["outer"]?.value else {
        Issue.record("Expected .dictionary for 'outer'")
        return
    }

    guard case .string(let value) = inner["inner"]?.value else {
        Issue.record("Expected .string for 'inner'")
        return
    }
    #expect(value == "value")
}

@Test func fromAnyWithNestedArrayInDictionary() {
    let input: [String: Any] = ["items": [1, 2, 3]]
    let result = AnyCodable(fromAny: input as Any)
    guard case .dictionary(let dict) = result.value else {
        Issue.record("Expected .dictionary, got \(result.value)")
        return
    }
    guard case .array(let items) = dict["items"]?.value else {
        Issue.record("Expected .array for 'items'")
        return
    }
    #expect(items.count == 3)
}

@Test func fromAnyWithUnsupportedTypeReturnsNull() {
    struct CustomType {}
    let result = AnyCodable(fromAny: CustomType() as Any)
    guard case .null = result.value else {
        Issue.record("Expected .null for unsupported type, got \(result.value)")
        return
    }
}

@Test func fromAnyWithNSNullReturnsNull() {
    let result = AnyCodable(fromAny: NSNull() as Any)
    guard case .null = result.value else {
        Issue.record("Expected .null for NSNull, got \(result.value)")
        return
    }
}