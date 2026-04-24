@testable import XcodeAssistantCopilotServer
import Synchronization
import Testing

@Suite struct AgentProgressFormatterTests {
    private let logger = MockLogger()
    private let formatter: AgentProgressFormatter

    init() {
        formatter = AgentProgressFormatter(logger: logger)
    }

    private func makeToolCall(name: String, arguments: String = "{}") -> ToolCall {
        ToolCall(
            index: 0,
            id: "call_\(name)",
            type: "function",
            function: ToolCallFunction(name: name, arguments: arguments)
        )
    }

    // MARK: - formattedToolCall: header

    @Test func formattedToolCallContainsToolName() {
        let toolCall = makeToolCall(name: "XcodeWrite")
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("`XcodeWrite`"))
    }

    @Test func formattedToolCallContainsToolLabel() {
        let toolCall = makeToolCall(name: "BuildProject")
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("**Running:**"))
    }

    @Test func formattedToolCallUsesUnknownWhenNameIsNil() {
        let toolCall = ToolCall(
            index: 0,
            id: "call_nil",
            type: "function",
            function: ToolCallFunction(name: nil, arguments: nil)
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("`unknown`"))
    }

    @Test func formattedToolCallShowsFilePathInHeader() {
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: #"{"filePath":"Sumatron2/Screens/Profile/UserSummaryView.swift","content":"import SwiftUI","tabIdentifier":"tab1"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("`Sumatron2/Screens/Profile/UserSummaryView.swift`"))
    }

    @Test func formattedToolCallShowsPathKeyAsFilePath() {
        let toolCall = makeToolCall(
            name: "ReadFile",
            arguments: #"{"path":"Sources/App.swift"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("`Sources/App.swift`"))
    }

    @Test func formattedToolCallShowsSourceFilePathKey() {
        let toolCall = makeToolCall(
            name: "EditFile",
            arguments: #"{"sourceFilePath":"Sources/View.swift","content":"struct V {}"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("`Sources/View.swift`"))
    }

    @Test func formattedToolCallOmitsFilePathWhenAbsent() {
        let toolCall = makeToolCall(
            name: "BuildProject",
            arguments: #"{"tabIdentifier":"windowtab3"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(!result.contains("**file:**"))
    }

    @Test func formattedToolCallHasLeadingNewline() {
        let toolCall = makeToolCall(name: "XcodeWrite")
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.hasPrefix("\n"))
    }

    @Test func formattedToolCallHasTrailingNewline() {
        let toolCall = makeToolCall(name: "XcodeWrite")
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.hasSuffix("\n"))
    }

    // MARK: - formattedToolCall: content code block

    @Test func formattedToolCallShowsMultilineContentAsCodeBlock() {
        let content = "import SwiftUI\n\nstruct Foo: View {\n    var body: some View { Text(\"hi\") }\n}"
        let encoded = content.replacing("\"", with: "\\\"").replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: "{\"content\":\"\(encoded)\",\"filePath\":\"Foo.swift\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("import SwiftUI"))
        #expect(result.contains("struct Foo"))
    }

    @Test func formattedToolCallWrapsContentInCodeFence() {
        let content = "import SwiftUI\nstruct Foo {}"
        let encoded = content.replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: "{\"content\":\"\(encoded)\",\"filePath\":\"Foo.swift\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        let fenceCount = result.components(separatedBy: "```").count - 1
        #expect(fenceCount >= 2)
    }

    @Test func formattedToolCallUsesFileExtensionAsCodeFenceLanguage() {
        let content = "import SwiftUI\nstruct Foo {}"
        let encoded = content.replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: "{\"content\":\"\(encoded)\",\"filePath\":\"Foo.swift\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("```swift"))
    }

    @Test func formattedToolCallUsesCorrectExtensionForPythonFile() {
        let content = "def hello():\n    print('hi')"
        let encoded = content.replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "WriteFile",
            arguments: "{\"content\":\"\(encoded)\",\"filePath\":\"script.py\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("```py"))
    }

    @Test func formattedToolCallUsesBlankFenceLanguageWhenNoFilePath() {
        let content = "some content\nwith newlines"
        let encoded = content.replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "WriteFile",
            arguments: "{\"content\":\"\(encoded)\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("```\n"))
    }

    @Test func formattedToolCallOmitsCodeBlockWhenNoContent() {
        let toolCall = makeToolCall(
            name: "BuildProject",
            arguments: #"{"tabIdentifier":"windowtab3"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(!result.contains("```"))
    }

    @Test func formattedToolCallDoesNotShowTabIdentifierInOutput() {
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: #"{"tabIdentifier":"windowtab3","filePath":"Foo.swift","content":"struct Foo {}"}"#
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(!result.contains("windowtab3"))
    }

    @Test func formattedToolCallPrefersMultilineContentOverShortStrings() {
        let longContent = "line1\nline2\nline3\nline4\nline5"
        let encoded = longContent.replacing("\n", with: "\\n")
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: "{\"label\":\"short\",\"content\":\"\(encoded)\",\"filePath\":\"Foo.swift\"}"
        )
        let result = formatter.formattedToolCall(toolCall)

        #expect(result.contains("line1"))
        #expect(!result.contains("short"))
    }

    // MARK: - formattedToolResult: empty / error

    @Test func formattedToolResultEmptyResultShowsDone() {
        let result = formatter.formattedToolResult("")

        #expect(result.contains("✓"))
        #expect(result.contains("Done"))
    }

    @Test func formattedToolResultWhitespaceOnlyShowsDone() {
        let result = formatter.formattedToolResult("   \n  ")

        #expect(result.contains("✓"))
    }

    @Test func formattedToolResultErrorPrefixShowsWarning() {
        let result = formatter.formattedToolResult("Error: something went wrong")

        #expect(result.contains("✗"))
        #expect(result.contains("something went wrong"))
    }

    @Test func formattedToolResultErrorExecutingToolShowsWarning() {
        let result = formatter.formattedToolResult("Error executing tool run_command: timeout")

        #expect(result.contains("✗"))
    }

    @Test func formattedToolResultSuccessfulPlainTextReturnsEmpty() {
        let result = formatter.formattedToolResult("struct Foo {}")

        #expect(result.isEmpty)
    }

    // MARK: - formattedToolResult: JSON success

    @Test func formattedToolResultJSONWithMessageFieldShowsMessage() {
        let json = #"{"success":true,"message":"Successfully overwrote file 'Foo.swift' (1530 bytes, 63 lines)","linesWritten":63,"bytesWritten":1530}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("Successfully overwrote file"))
        #expect(result.contains("✓"))
    }

    @Test func formattedToolResultJSONBuildSuccessShowsBuildResult() {
        let json = #"{"buildResult":"The project built successfully.","elapsedTime":12.77,"errors":[]}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("The project built successfully."))
        #expect(result.contains("✓"))
    }

    @Test func formattedToolResultJSONWithNoErrorsAndNoMessageShowsDone() {
        let json = #"{"success":true,"errors":[]}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("✓"))
    }

    // MARK: - formattedToolResult: JSON failure

    @Test func formattedToolResultJSONSuccessFalseShowsWarning() {
        let json = #"{"success":false,"message":"File not found"}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("✗"))
        #expect(result.contains("File not found"))
    }

    @Test func formattedToolResultJSONWithErrorsArrayShowsWarning() {
        let json = #"{"buildResult":"failed","errors":[{"message":"Use of undeclared identifier 'Foo'"}]}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("✗"))
        #expect(result.contains("Use of undeclared identifier 'Foo'"))
    }

    @Test func formattedToolResultJSONWithMultipleErrorsShowsAll() {
        let json = #"{"errors":[{"message":"Error A"},{"message":"Error B"}]}"#
        let result = formatter.formattedToolResult(json)

        #expect(result.contains("Error A"))
        #expect(result.contains("Error B"))
    }

    @Test func formattedToolCallLogsMalformedJSON() {
        let toolCall = makeToolCall(
            name: "XcodeWrite",
            arguments: "{malformed json"
        )
        let _ = formatter.formattedToolCall(toolCall)

        #expect(logger.debugMessages.contains(where: { $0.contains("Failed to parse JSON") }))
    }

    @Test func formattedToolResultLogsMalformedJSON() {
        let _ = formatter.formattedToolResult("{not valid json")

        #expect(logger.debugMessages.contains(where: { $0.contains("Failed to parse JSON") }))
    }
}
