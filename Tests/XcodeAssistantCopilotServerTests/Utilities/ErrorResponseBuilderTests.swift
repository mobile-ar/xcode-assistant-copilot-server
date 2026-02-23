import Foundation
import HTTPTypes
import Testing
@testable import XcodeAssistantCopilotServer

@Test func buildErrorResponseDefaultTypeIsApiError() {
    let response = ErrorResponseBuilder.build(
        status: .badRequest,
        message: "Something went wrong"
    )

    #expect(response.status == .badRequest)
    #expect(response.headers[.contentType] == "application/json")
}

@Test func buildErrorResponseWithCustomType() {
    let response = ErrorResponseBuilder.build(
        status: .badRequest,
        type: "invalid_request_error",
        message: "Model is required"
    )

    #expect(response.status == .badRequest)
    #expect(response.headers[.contentType] == "application/json")
}

@Test func buildErrorResponseUnauthorizedStatus() {
    let response = ErrorResponseBuilder.build(
        status: .unauthorized,
        message: "Authentication failed"
    )

    #expect(response.status == .unauthorized)
}

@Test func buildErrorResponseInternalServerErrorStatus() {
    let response = ErrorResponseBuilder.build(
        status: .internalServerError,
        type: "api_error",
        message: "Failed to list models"
    )

    #expect(response.status == .internalServerError)
}

@Test func buildErrorResponseWithEmptyMessage() {
    let response = ErrorResponseBuilder.build(
        status: .badRequest,
        message: ""
    )

    #expect(response.status == .badRequest)
    #expect(response.headers[.contentType] == "application/json")
}

@Test func buildErrorResponseBodyMatchesExpectedJSON() throws {
    let type = "invalid_request_error"
    let message = "Details with \"quotes\" and <special> chars"

    let expectedBody: [String: [String: String]] = [
        "error": [
            "message": message,
            "type": type,
        ],
    ]

    let expectedData = try JSONEncoder().encode(expectedBody)
    let decoded = try JSONDecoder().decode([String: [String: String]].self, from: expectedData)

    #expect(decoded["error"]?["message"] == message)
    #expect(decoded["error"]?["type"] == type)
    #expect(decoded.count == 1)
    #expect(decoded["error"]?.count == 2)
}

@Test func buildErrorResponseSetsContentTypeHeader() {
    let response = ErrorResponseBuilder.build(
        status: .notFound,
        message: "Not found"
    )

    #expect(response.headers[.contentType] == "application/json")
}