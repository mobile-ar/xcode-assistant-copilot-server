@testable import XcodeAssistantCopilotServer
import Foundation
import Testing

@Test func toOpenAIToolSetsTypeFunctionAndMapsFields() {
    let tool = MCPTool(
        name: "search",
        description: "Search for files",
        inputSchema: [
            "type": AnyCodable(.string("object")),
            "properties": AnyCodable(.dictionary([
                "query": AnyCodable(.dictionary(["type": AnyCodable(.string("string"))]))
            ]))
        ]
    )

    let openAITool = tool.toOpenAITool()

    #expect(openAITool.type == "function")
    #expect(openAITool.function.name == "search")
    #expect(openAITool.function.description == "Search for files")
    #expect(openAITool.function.parameters != nil)
    #expect(openAITool.function.parameters?["type"] != nil)
    #expect(openAITool.function.parameters?["properties"] != nil)
}

@Test func toOpenAIToolWithNilDescriptionAndSchema() {
    let tool = MCPTool(name: "simple_tool")

    let openAITool = tool.toOpenAITool()

    #expect(openAITool.type == "function")
    #expect(openAITool.function.name == "simple_tool")
    #expect(openAITool.function.description == nil)
    #expect(openAITool.function.parameters == nil)
}

@Test func initFromMCPToolDefinitionCopiesAllFields() {
    let definition = MCPToolDefinition(
        name: "read_file",
        description: "Reads a file from disk",
        inputSchema: [
            "type": AnyCodable(.string("object")),
            "properties": AnyCodable(.dictionary([
                "path": AnyCodable(.dictionary(["type": AnyCodable(.string("string"))]))
            ])),
            "required": AnyCodable(.array([AnyCodable(.string("path"))]))
        ]
    )

    let tool = MCPTool(from: definition)

    #expect(tool.name == "read_file")
    #expect(tool.description == "Reads a file from disk")
    #expect(tool.inputSchema != nil)
    #expect(tool.inputSchema?["type"] != nil)
    #expect(tool.inputSchema?["properties"] != nil)
    #expect(tool.inputSchema?["required"] != nil)
}

@Test func initFromMCPToolDefinitionWithNilOptionals() {
    let definition = MCPToolDefinition(name: "no_extras")

    let tool = MCPTool(from: definition)

    #expect(tool.name == "no_extras")
    #expect(tool.description == nil)
    #expect(tool.inputSchema == nil)
}

@Test func textContentReturnsJoinedTextItems() {
    let result = MCPToolResult(content: [
        MCPToolResultContent(type: "text", text: "first line"),
        MCPToolResultContent(type: "text", text: "second line")
    ])

    #expect(result.textContent == "first line\nsecond line")
}

@Test func textContentFiltersByTextType() {
    let result = MCPToolResult(content: [
        MCPToolResultContent(type: "text", text: "visible"),
        MCPToolResultContent(type: "image", text: "ignored"),
        MCPToolResultContent(type: "text", text: "also visible")
    ])

    #expect(result.textContent == "visible\nalso visible")
}

@Test func textContentReturnsEmptyForNoTextItems() {
    let result = MCPToolResult(content: [
        MCPToolResultContent(type: "image", text: "not text")
    ])

    #expect(result.textContent == "")
}

@Test func textContentReturnsEmptyForEmptyContent() {
    let result = MCPToolResult(content: [])

    #expect(result.textContent == "")
}

@Test func textContentSkipsNilTextFields() {
    let result = MCPToolResult(content: [
        MCPToolResultContent(type: "text", text: nil),
        MCPToolResultContent(type: "text", text: "has text")
    ])

    #expect(result.textContent == "has text")
}

@Test func mcpToolResultIsErrorDefault() {
    let result = MCPToolResult(content: [])
    #expect(result.isError == false)
}

@Test func mcpToolResultIsErrorWhenSet() {
    let result = MCPToolResult(content: [], isError: true)
    #expect(result.isError == true)
}

@Test func mcpToolResultContentInit() {
    let content = MCPToolResultContent(type: "text", text: "hello")
    #expect(content.type == "text")
    #expect(content.text == "hello")
}

@Test func mcpToolResultContentInitWithNilText() {
    let content = MCPToolResultContent(type: "image")
    #expect(content.type == "image")
    #expect(content.text == nil)
}

@Test func mcpToolErrorToolNotFoundDescription() {
    let error = MCPToolError.toolNotFound("missing_tool")
    #expect(error.description.contains("missing_tool"))
    #expect(error.description.contains("not found"))
}

@Test func mcpToolErrorExecutionFailedDescription() {
    let error = MCPToolError.executionFailed("timeout occurred")
    #expect(error.description.contains("timeout occurred"))
    #expect(error.description.contains("execution failed"))
}

@Test func mcpToolErrorBridgeNotAvailableDescription() {
    let error = MCPToolError.bridgeNotAvailable
    #expect(error.description.contains("not available"))
}

@Test func toOpenAIToolRoundTripEncodesCorrectly() throws {
    let tool = MCPTool(
        name: "test_tool",
        description: "A test tool",
        inputSchema: [
            "type": AnyCodable(.string("object")),
            "properties": AnyCodable(.dictionary([
                "input": AnyCodable(.dictionary(["type": AnyCodable(.string("string"))]))
            ]))
        ]
    )

    let openAITool = tool.toOpenAITool()
    let data = try JSONEncoder().encode(openAITool)
    let decoded = try JSONDecoder().decode(Tool.self, from: data)

    #expect(decoded.type == "function")
    #expect(decoded.function.name == "test_tool")
    #expect(decoded.function.description == "A test tool")
    #expect(decoded.function.parameters != nil)
}

@Test func textContentWithSingleItem() {
    let result = MCPToolResult(content: [
        MCPToolResultContent(type: "text", text: "only one")
    ])

    #expect(result.textContent == "only one")
}

@Test func mcpToolInitStoresAllFields() {
    let schema: [String: AnyCodable] = ["type": AnyCodable(.string("object"))]
    let tool = MCPTool(name: "my_tool", description: "desc", inputSchema: schema)

    #expect(tool.name == "my_tool")
    #expect(tool.description == "desc")
    #expect(tool.inputSchema != nil)
}

@Test func mcpToolInitWithDefaultNils() {
    let tool = MCPTool(name: "bare_tool")

    #expect(tool.name == "bare_tool")
    #expect(tool.description == nil)
    #expect(tool.inputSchema == nil)
}