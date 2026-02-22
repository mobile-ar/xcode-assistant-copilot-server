import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func decodesSuccessResponseWithContent() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
            "content": [
                {"type": "text", "text": "Hello, world!"}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == 1)
    #expect(response.isSuccess)
    #expect(response.error == nil)
    #expect(response.result?.content?.count == 1)
    #expect(response.result?.content?.first?.type == "text")
    #expect(response.result?.content?.first?.text == "Hello, world!")
}

@Test func decodesErrorResponse() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 2,
        "error": {
            "code": -32600,
            "message": "Invalid Request"
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == 2)
    #expect(!response.isSuccess)
    #expect(response.error?.code == -32600)
    #expect(response.error?.message == "Invalid Request")
    #expect(response.result == nil)
}

@Test func decodesResponseWithNoResult() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 3
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == 3)
    #expect(response.isSuccess)
    #expect(response.result != nil)
    #expect(response.result?.content == nil)
    #expect(response.result?.tools == nil)
}

@Test func decodesResponseWithEmptyResult() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 4,
        "result": {}
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == 4)
    #expect(response.isSuccess)
    #expect(response.result != nil)
    #expect(response.result?.content == nil)
    #expect(response.result?.tools == nil)
    #expect(response.result?.capabilities == nil)
}

@Test func decodesResponseWithTools() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 5,
        "result": {
            "tools": [
                {
                    "name": "read_file",
                    "description": "Reads a file from disk",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string"}
                        }
                    }
                },
                {
                    "name": "write_file"
                }
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.result?.tools?.count == 2)

    let firstTool = try #require(response.result?.tools?.first)
    #expect(firstTool.name == "read_file")
    #expect(firstTool.description == "Reads a file from disk")
    #expect(firstTool.inputSchema != nil)

    let secondTool = try #require(response.result?.tools?[1])
    #expect(secondTool.name == "write_file")
    #expect(secondTool.description == nil)
    #expect(secondTool.inputSchema == nil)
}

@Test func decodesResponseWithCapabilities() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 6,
        "result": {
            "capabilities": {
                "tools": {
                    "listChanged": true
                }
            }
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.result?.capabilities?.tools?.listChanged == true)
}

@Test func decodesCapabilitiesWithoutToolsCapability() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 7,
        "result": {
            "capabilities": {}
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.result?.capabilities != nil)
    #expect(response.result?.capabilities?.tools == nil)
}

@Test func decodesResponseWithNullId() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": null,
        "result": {}
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == nil)
    #expect(response.isSuccess)
}

@Test func decodesResponseWithMissingId() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "result": {}
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.id == nil)
    #expect(response.isSuccess)
}

@Test func rawDictionaryContainsAllResultKeys() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 8,
        "result": {
            "protocolVersion": "2024-11-05",
            "serverInfo": {
                "name": "test-server",
                "version": "1.0.0"
            }
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    #expect(raw["protocolVersion"] != nil)
    #expect(raw["serverInfo"] != nil)
}

@Test func patchStructuredContentFromTextJSON() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 9,
        "result": {
            "content": [
                {"type": "text", "text": "{\\"key\\": \\"value\\"}"}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    let structured = try #require(raw["structuredContent"])
    if case .dictionary(let dict) = structured.value {
        if case .string(let val) = dict["key"]?.value {
            #expect(val == "value")
        } else {
            Issue.record("Expected string value for key")
        }
    } else {
        Issue.record("Expected dictionary for structuredContent")
    }
}

@Test func patchStructuredContentFromPlainText() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 10,
        "result": {
            "content": [
                {"type": "text", "text": "just plain text"}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    let structured = try #require(raw["structuredContent"])
    if case .dictionary(let dict) = structured.value {
        if case .string(let val) = dict["text"]?.value {
            #expect(val == "just plain text")
        } else {
            Issue.record("Expected string value for text key")
        }
    } else {
        Issue.record("Expected dictionary for structuredContent")
    }
}

@Test func patchStructuredContentSkipsWhenAlreadyPresent() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 11,
        "result": {
            "content": [
                {"type": "text", "text": "ignored"}
            ],
            "structuredContent": {"existing": true}
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    let structured = try #require(raw["structuredContent"])
    if case .dictionary(let dict) = structured.value {
        #expect(dict["existing"] != nil)
        #expect(dict["text"] == nil)
    } else {
        Issue.record("Expected dictionary for structuredContent")
    }
}

@Test func patchStructuredContentSkipsWhenNoContent() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 12,
        "result": {
            "protocolVersion": "2024-11-05"
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    #expect(raw["structuredContent"] == nil)
}

@Test func patchStructuredContentSkipsWhenContentIsEmpty() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 13,
        "result": {
            "content": []
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    #expect(raw["structuredContent"] == nil)
}

@Test func patchStructuredContentSkipsWhenNoTextTypeContent() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 14,
        "result": {
            "content": [
                {"type": "image", "text": null}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    #expect(raw["structuredContent"] == nil)
}

@Test func decodesMultipleContentItems() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 15,
        "result": {
            "content": [
                {"type": "text", "text": "first"},
                {"type": "text", "text": "second"},
                {"type": "image"}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    #expect(response.result?.content?.count == 3)
    #expect(response.result?.content?[0].text == "first")
    #expect(response.result?.content?[1].text == "second")
    #expect(response.result?.content?[2].type == "image")
    #expect(response.result?.content?[2].text == nil)
}

@Test func decodesToolWithInputSchemaNestedObjects() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 16,
        "result": {
            "tools": [
                {
                    "name": "complex_tool",
                    "description": "A tool with nested schema",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "nested": {
                                "type": "object",
                                "properties": {
                                    "inner": {"type": "string"}
                                }
                            },
                            "list": {
                                "type": "array",
                                "items": {"type": "number"}
                            }
                        },
                        "required": ["nested"]
                    }
                }
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let tool = try #require(response.result?.tools?.first)
    #expect(tool.name == "complex_tool")
    #expect(tool.inputSchema != nil)
    #expect(tool.inputSchema?["type"] != nil)
    #expect(tool.inputSchema?["properties"] != nil)
    #expect(tool.inputSchema?["required"] != nil)
}

@Test func invalidJSONThrowsDecodingError() {
    let data = Data("not json".utf8)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(MCPResponse.self, from: data)
    }
}

@Test func mcpResponseManualInit() {
    let error = MCPError(code: -1, message: "test error")
    let response = MCPResponse(id: 99, result: nil, error: error)

    #expect(response.id == 99)
    #expect(!response.isSuccess)
    #expect(response.error?.code == -1)
    #expect(response.error?.message == "test error")
}

@Test func mcpResultDefaultInit() {
    let result = MCPResult()
    #expect(result.content == nil)
    #expect(result.tools == nil)
    #expect(result.capabilities == nil)
    #expect(result.raw.isEmpty)
}

@Test func mcpContentInit() {
    let content = MCPContent(type: "text", text: "hello")
    #expect(content.type == "text")
    #expect(content.text == "hello")
}

@Test func mcpCapabilitiesInit() {
    let cap = MCPCapabilities(tools: MCPToolsCapability(listChanged: true))
    #expect(cap.tools?.listChanged == true)
}

@Test func mcpToolDefinitionInit() {
    let tool = MCPToolDefinition(name: "my_tool", description: "desc", inputSchema: ["type": AnyCodable(.string("object"))])
    #expect(tool.name == "my_tool")
    #expect(tool.description == "desc")
    #expect(tool.inputSchema?["type"] != nil)
}

@Test func mcpParseErrorDescription() {
    let error = MCPParseError.invalidJSON
    #expect(error.description == "Failed to parse MCP response as JSON")
}

@Test func patchStructuredContentWithJSONArray() throws {
    let json = """
    {
        "jsonrpc": "2.0",
        "id": 17,
        "result": {
            "content": [
                {"type": "text", "text": "[1, 2, 3]"}
            ]
        }
    }
    """
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(MCPResponse.self, from: data)

    let raw = try #require(response.result?.raw)
    let structured = try #require(raw["structuredContent"])
    if case .array(let arr) = structured.value {
        #expect(arr.count == 3)
    } else {
        Issue.record("Expected array for structuredContent parsed from JSON array text")
    }
}