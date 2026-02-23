import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func sseEventIsDoneReturnsTrueForDoneData() {
    let event = SSEEvent(data: "[DONE]")
    #expect(event.isDone == true)
}

@Test func sseEventIsDoneReturnsFalseForRegularData() {
    let event = SSEEvent(data: "{\"id\":\"123\"}")
    #expect(event.isDone == false)
}

@Test func sseEventIsDoneReturnsFalseForEmptyData() {
    let event = SSEEvent(data: "")
    #expect(event.isDone == false)
}

@Test func sseEventIsDoneReturnsFalseForPartialDone() {
    let event = SSEEvent(data: "[DONE")
    #expect(event.isDone == false)
}

@Test func sseEventInitWithAllFields() {
    let event = SSEEvent(data: "test data", event: "message", id: "42")
    #expect(event.data == "test data")
    #expect(event.event == "message")
    #expect(event.id == "42")
}

@Test func sseEventInitWithDataOnly() {
    let event = SSEEvent(data: "only data")
    #expect(event.data == "only data")
    #expect(event.event == nil)
    #expect(event.id == nil)
}

@Test func sseEventDecodeDataSucceeds() throws {
    struct TestPayload: Decodable {
        let id: String
        let value: Int
    }

    let event = SSEEvent(data: "{\"id\":\"abc\",\"value\":42}")
    let payload = try event.decodeData(TestPayload.self)
    #expect(payload.id == "abc")
    #expect(payload.value == 42)
}

@Test func sseEventDecodeDataThrowsOnInvalidJSON() {
    let event = SSEEvent(data: "not json at all")
    #expect(throws: (any Error).self) {
        try event.decodeData(ChatCompletionChunk.self)
    }
}

@Test func sseEventDecodeDataThrowsOnEmptyString() {
    let event = SSEEvent(data: "")
    #expect(throws: (any Error).self) {
        try event.decodeData(ChatCompletionChunk.self)
    }
}

@Test func sseEventDecodeDataWithChatCompletionChunk() throws {
    let json = """
    {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.id == "chatcmpl-123")
    #expect(chunk.model == "gpt-4")
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices.first?.delta?.content == "Hello")
    #expect(chunk.choices.first?.finishReason == nil)
}

@Test func sseEventDecodeDataWithStopFinishReason() throws {
    let json = """
    {"id":"chatcmpl-456","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.choices.first?.finishReason == "stop")
}

@Test func sseEventDecodeDataWithToolCallsFinishReason() throws {
    let json = """
    {"id":"chatcmpl-789","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.choices.first?.finishReason == "tool_calls")
}

@Test func sseParserParseLineWithDataPrefix() {
    let parser = SSEParser()
    let event = parser.parseLine("data: {\"test\":true}")
    #expect(event != nil)
    #expect(event?.data == "{\"test\":true}")
}

@Test func sseParserParseLineWithDataPrefixNoSpace() {
    let parser = SSEParser()
    let event = parser.parseLine("data:{\"test\":true}")
    #expect(event != nil)
    #expect(event?.data == "{\"test\":true}")
}

@Test func sseParserParseLineWithDone() {
    let parser = SSEParser()
    let event = parser.parseLine("data: [DONE]")
    #expect(event != nil)
    #expect(event?.isDone == true)
}

@Test func sseParserParseLineReturnsNilForNonDataLine() {
    let parser = SSEParser()
    #expect(parser.parseLine("event: message") == nil)
    #expect(parser.parseLine("id: 42") == nil)
    #expect(parser.parseLine(": comment") == nil)
    #expect(parser.parseLine("") == nil)
    #expect(parser.parseLine("random text") == nil)
}

@Test func sseParserParseLineReturnsNilForEmptyDataLine() {
    let parser = SSEParser()
    let event = parser.parseLine("data: ")
    // "data: " with just a space results in empty string after trimming the space
    // The extractFieldValue strips one leading space, leaving ""
    #expect(event == nil)
}

@Test func sseParserParseLinePreservesWhitespaceInData() {
    let parser = SSEParser()
    let event = parser.parseLine("data:  multiple  spaces  ")
    #expect(event != nil)
    #expect(event?.data == " multiple  spaces  ")
}

@Test func sseParserParseLineWithJSONData() {
    let parser = SSEParser()
    let json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"choices\":[]}"
    let event = parser.parseLine("data: \(json)")
    #expect(event != nil)
    #expect(event?.data == json)
}

@Test func sseParserParseLineStripsExactlyOneLeadingSpace() {
    let parser = SSEParser()
    let event1 = parser.parseLine("data: hello")
    #expect(event1?.data == "hello")

    let event2 = parser.parseLine("data:hello")
    #expect(event2?.data == "hello")

    let event3 = parser.parseLine("data:  hello")
    #expect(event3?.data == " hello")
}

@Test func sseParserErrorDescriptions() {
    let invalidData = SSEParserError.invalidData("bad encoding")
    #expect(invalidData.description.contains("bad encoding"))
    #expect(invalidData.description.contains("Invalid SSE data"))

    let interrupted = SSEParserError.streamInterrupted
    #expect(interrupted.description.contains("interrupted"))
}

@Test func sseParserErrorInvalidDataDescription() {
    let error = SSEParserError.invalidData("cannot decode")
    #expect(error.description == "Invalid SSE data: cannot decode")
}

@Test func sseParserErrorStreamInterruptedDescription() {
    let error = SSEParserError.streamInterrupted
    #expect(error.description == "SSE stream was interrupted")
}

@Test func sseParserInit() {
    let parser = SSEParser()
    _ = parser
}

@Test func sseEventDecodeDataWithNestedJSON() throws {
    struct Nested: Decodable {
        let outer: Inner
        struct Inner: Decodable {
            let value: String
        }
    }

    let event = SSEEvent(data: "{\"outer\":{\"value\":\"deep\"}}")
    let decoded = try event.decodeData(Nested.self)
    #expect(decoded.outer.value == "deep")
}

@Test func sseEventDecodeDataWithTypeMismatch() {
    struct Expected: Decodable {
        let count: Int
    }

    let event = SSEEvent(data: "{\"count\":\"not_a_number\"}")
    #expect(throws: (any Error).self) {
        try event.decodeData(Expected.self)
    }
}

@Test func sseEventDecodeDataWithMissingRequiredField() {
    struct Expected: Decodable {
        let requiredField: String
    }

    let event = SSEEvent(data: "{\"otherField\":\"value\"}")
    #expect(throws: (any Error).self) {
        try event.decodeData(Expected.self)
    }
}

@Test func sseParserParseLineWithLongData() {
    let parser = SSEParser()
    let longString = String(repeating: "a", count: 10000)
    let event = parser.parseLine("data: \(longString)")
    #expect(event != nil)
    #expect(event?.data.count == 10000)
}

@Test func sseParserParseLineWithSpecialCharacters() {
    let parser = SSEParser()
    let event = parser.parseLine("data: {\"text\":\"hello\\nworld\\t\\\"quoted\\\"\"}")
    #expect(event != nil)
    #expect(event?.data.contains("hello") == true)
}

@Test func sseParserParseLineWithUnicodeData() {
    let parser = SSEParser()
    let event = parser.parseLine("data: {\"emoji\":\"🚀\",\"japanese\":\"日本語\"}")
    #expect(event != nil)
    #expect(event?.data.contains("🚀") == true)
    #expect(event?.data.contains("日本語") == true)
}

@Test func sseEventDataPreservesExactContent() {
    let data = "{\"choices\":[{\"delta\":{\"content\":\"Hello, world!\"},\"index\":0}]}"
    let event = SSEEvent(data: data)
    #expect(event.data == data)
}

@Test func sseParserParseLineWithColonInData() {
    let parser = SSEParser()
    let event = parser.parseLine("data: key:value:extra")
    #expect(event != nil)
    #expect(event?.data == "key:value:extra")
}

@Test func sseEventDecodeDataWithRoleDelta() throws {
    let json = """
    {"id":"chatcmpl-100","object":"chat.completion.chunk","created":1700000000,"model":"copilot","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.choices.first?.delta?.role == .assistant)
    #expect(chunk.choices.first?.delta?.content == nil)
}

@Test func sseEventDecodeDataWithToolCallDelta() throws {
    let json = """
    {"id":"chatcmpl-200","object":"chat.completion.chunk","created":1700000000,"model":"copilot","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"search","arguments":""}}]},"finish_reason":null}]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    let toolCalls = chunk.choices.first?.delta?.toolCalls
    #expect(toolCalls?.count == 1)
    #expect(toolCalls?.first?.id == "call_abc")
    #expect(toolCalls?.first?.function.name == "search")
    #expect(toolCalls?.first?.function.arguments == "")
}

@Test func sseEventDecodeDataWithEmptyChoices() throws {
    let json = """
    {"id":"chatcmpl-300","object":"chat.completion.chunk","created":1700000000,"model":"copilot","choices":[]}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.choices.isEmpty)
}

@Test func sseEventDecodeDataWithSystemFingerprint() throws {
    let json = """
    {"id":"chatcmpl-400","object":"chat.completion.chunk","created":1700000000,"model":"copilot","choices":[],"system_fingerprint":"fp_abc123"}
    """
    let event = SSEEvent(data: json)
    let chunk = try event.decodeData(ChatCompletionChunk.self)
    #expect(chunk.systemFingerprint == "fp_abc123")
}

@Test func sseParserParseLineDataPrefixCaseSensitive() {
    let parser = SSEParser()
    let upper = parser.parseLine("DATA: hello")
    #expect(upper == nil)

    let mixed = parser.parseLine("Data: hello")
    #expect(mixed == nil)
}

@Test func sseParserFlushesEventWhenNewEventFieldArrivesWithoutBlankLine() async throws {
    let parser = SSEParser()

    let lines = [
        "event: response.created",
        "data: {\"type\":\"response.created\",\"sequence_number\":0}",
        "event: response.completed",
        "data: {\"type\":\"response.completed\",\"sequence_number\":106}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 2)
    #expect(collected[0].event == "response.created")
    #expect(collected[0].data == "{\"type\":\"response.created\",\"sequence_number\":0}")
    #expect(collected[1].event == "response.completed")
    #expect(collected[1].data == "{\"type\":\"response.completed\",\"sequence_number\":106}")
}

@Test func sseParserFlushesMultipleEventsWithoutBlankLines() async throws {
    let parser = SSEParser()

    let lines = [
        "event: response.created",
        "data: {\"type\":\"response.created\"}",
        "event: response.in_progress",
        "data: {\"type\":\"response.in_progress\"}",
        "event: response.output_text.delta",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}",
        "event: response.completed",
        "data: {\"type\":\"response.completed\"}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 4)
    #expect(collected[0].event == "response.created")
    #expect(collected[1].event == "response.in_progress")
    #expect(collected[2].event == "response.output_text.delta")
    #expect(collected[2].data.contains("Hello"))
    #expect(collected[3].event == "response.completed")
}

@Test func sseParserHandlesMixOfBlankLineAndNoBlankLineSeparators() async throws {
    let parser = SSEParser()

    let lines = [
        "event: response.created",
        "data: {\"type\":\"response.created\"}",
        "",
        "event: response.output_text.delta",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}",
        "event: response.completed",
        "data: {\"type\":\"response.completed\"}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 3)
    #expect(collected[0].event == "response.created")
    #expect(collected[1].event == "response.output_text.delta")
    #expect(collected[1].data.contains("Hi"))
    #expect(collected[2].event == "response.completed")
}

@Test func sseParserPreservesIdAcrossFlush() async throws {
    let parser = SSEParser()

    let lines = [
        "id: 1",
        "event: first",
        "data: {\"n\":1}",
        "id: 2",
        "event: second",
        "data: {\"n\":2}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 2)
    #expect(collected[0].event == "first")
    #expect(collected[0].id == "1")
    #expect(collected[0].data == "{\"n\":1}")
    #expect(collected[1].event == "second")
    #expect(collected[1].id == "2")
    #expect(collected[1].data == "{\"n\":2}")
}

@Test func sseParserFlushDoesNotOccurWhenNoDataAccumulated() async throws {
    let parser = SSEParser()

    let lines = [
        "event: first",
        "event: second",
        "data: {\"only\":\"event\"}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 1)
    #expect(collected[0].event == "second")
    #expect(collected[0].data == "{\"only\":\"event\"}")
}

@Test func sseParserFlushWithMultipleDataLinesPerEvent() async throws {
    let parser = SSEParser()

    let lines = [
        "event: first",
        "data: line1",
        "data: line2",
        "event: second",
        "data: single",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 2)
    #expect(collected[0].event == "first")
    #expect(collected[0].data == "line1\nline2")
    #expect(collected[1].event == "second")
    #expect(collected[1].data == "single")
}

@Test func sseParserNoBlankLineSeparatorWithLargePayloads() async throws {
    let parser = SSEParser()

    let createdPayload = "{\"type\":\"response.created\",\"response\":{\"id\":\"resp_001\",\"status\":\"in_progress\",\"background\":false,\"completed_at\":null}}"
    let completedPayload = "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_001\",\"status\":\"completed\",\"background\":false,\"completed_at\":1234567890}}"

    let lines = [
        "event: response.created",
        "data: \(createdPayload)",
        "event: response.completed",
        "data: \(completedPayload)",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 2)
    #expect(collected[0].event == "response.created")
    #expect(collected[0].data == createdPayload)
    #expect(collected[1].event == "response.completed")
    #expect(collected[1].data == completedPayload)

    let createdJSON = try JSONSerialization.jsonObject(with: Data(collected[0].data.utf8)) as? [String: Any]
    #expect(createdJSON?["type"] as? String == "response.created")

    let completedJSON = try JSONSerialization.jsonObject(with: Data(collected[1].data.utf8)) as? [String: Any]
    #expect(completedJSON?["type"] as? String == "response.completed")
}

@Test func sseParserNormalBlankLineSeparatedEventsStillWork() async throws {
    let parser = SSEParser()

    let lines = [
        "event: response.created",
        "data: {\"type\":\"response.created\"}",
        "",
        "event: response.output_text.delta",
        "data: {\"delta\":\"Hello \"}",
        "",
        "event: response.output_text.delta",
        "data: {\"delta\":\"world\"}",
        "",
        "event: response.completed",
        "data: {\"type\":\"response.completed\"}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 4)
    #expect(collected[0].event == "response.created")
    #expect(collected[1].event == "response.output_text.delta")
    #expect(collected[2].event == "response.output_text.delta")
    #expect(collected[3].event == "response.completed")
}

@Test func sseParserFlushesOnEndOfStreamWithoutTrailingBlankLine() async throws {
    let parser = SSEParser()

    let lines = [
        "event: response.created",
        "data: {\"type\":\"response.created\"}",
        "event: response.completed",
        "data: {\"type\":\"response.completed\"}"
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 2)
    #expect(collected[0].event == "response.created")
    #expect(collected[0].data == "{\"type\":\"response.created\"}")
    #expect(collected[1].event == "response.completed")
    #expect(collected[1].data == "{\"type\":\"response.completed\"}")
}

@Test func sseParserDataOnlyEventsWithoutBlankLineSeparatorsNoFlush() async throws {
    let parser = SSEParser()

    let lines = [
        "data: {\"type\":\"response.created\"}",
        "data: {\"type\":\"response.completed\"}",
        ""
    ]

    let stream = parser.parseLines(AsyncThrowingStream { continuation in
        for line in lines { continuation.yield(line) }
        continuation.finish()
    })

    var collected: [SSEEvent] = []
    for try await event in stream {
        collected.append(event)
    }

    #expect(collected.count == 1)
    #expect(collected[0].data == "{\"type\":\"response.created\"}\n{\"type\":\"response.completed\"}")
    #expect(collected[0].event == nil)
}