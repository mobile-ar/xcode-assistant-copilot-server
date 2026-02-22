import Testing
import Foundation
@testable import XcodeAssistantCopilotServer

@Test func asyncDataStreamYieldsWrittenData() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    let message = "hello world"
    pipe.fileHandleForWriting.write(Data(message.utf8))
    pipe.fileHandleForWriting.closeFile()

    var collected = Data()
    for await data in stream {
        collected.append(data)
    }

    #expect(String(data: collected, encoding: .utf8) == message)
}

@Test func asyncDataStreamFinishesOnEOF() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    pipe.fileHandleForWriting.closeFile()

    var count = 0
    for await _ in stream {
        count += 1
    }

    #expect(count == 0)
}

@Test func asyncDataStreamYieldsMultipleChunks() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    let messages = ["first\n", "second\n", "third\n"]
    Task {
        for msg in messages {
            pipe.fileHandleForWriting.write(Data(msg.utf8))
            try? await Task.sleep(for: .milliseconds(50))
        }
        pipe.fileHandleForWriting.closeFile()
    }

    var collected = Data()
    for await data in stream {
        collected.append(data)
    }

    let result = String(data: collected, encoding: .utf8)
    #expect(result == "first\nsecond\nthird\n")
}

@Test func asyncDataStreamRespectsTaskCancellation() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    pipe.fileHandleForWriting.write(Data("initial".utf8))

    let task = Task {
        var chunks = 0
        for await _ in stream {
            chunks += 1
            break
        }
        return chunks
    }

    let chunks = await task.value
    #expect(chunks == 1)

    pipe.fileHandleForWriting.closeFile()
}

@Test func asyncDataStreamHandlesLargeData() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    let largeString = String(repeating: "A", count: 100_000)
    Task {
        pipe.fileHandleForWriting.write(Data(largeString.utf8))
        pipe.fileHandleForWriting.closeFile()
    }

    var collected = Data()
    for await data in stream {
        collected.append(data)
    }

    #expect(collected.count == largeString.utf8.count)
    #expect(String(data: collected, encoding: .utf8) == largeString)
}

@Test func asyncDataStreamHandlesUTF8Content() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    let message = "こんにちは世界 🌍 émoji"
    Task {
        pipe.fileHandleForWriting.write(Data(message.utf8))
        pipe.fileHandleForWriting.closeFile()
    }

    var collected = Data()
    for await data in stream {
        collected.append(data)
    }

    #expect(String(data: collected, encoding: .utf8) == message)
}

@Test func asyncDataStreamDeliversNewlineDelimitedMessages() async {
    let pipe = Pipe()
    let stream = pipe.fileHandleForReading.asyncDataStream()

    let jsonMessages = [
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n",
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[]}}\n",
    ]

    Task {
        for msg in jsonMessages {
            pipe.fileHandleForWriting.write(Data(msg.utf8))
            try? await Task.sleep(for: .milliseconds(30))
        }
        pipe.fileHandleForWriting.closeFile()
    }

    var collected = Data()
    for await data in stream {
        collected.append(data)
    }

    let result = String(data: collected, encoding: .utf8)
    #expect(result == jsonMessages.joined())
}