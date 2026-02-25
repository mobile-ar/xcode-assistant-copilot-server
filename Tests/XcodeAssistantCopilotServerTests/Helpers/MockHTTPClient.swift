@testable import XcodeAssistantCopilotServer
import Foundation

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var executeResults: [Result<DataResponse, Error>] = []
    var streamResults: [Result<StreamResponse, Error>] = []
    private(set) var sentEndpoints: [any Endpoint] = []
    private(set) var executeCallCount = 0
    private(set) var streamCallCount = 0

    func execute(_ endpoint: any Endpoint) async throws -> DataResponse {
        sentEndpoints.append(endpoint)
        let index = executeCallCount
        executeCallCount += 1
        guard index < executeResults.count else {
            return DataResponse(data: Data(), statusCode: 200)
        }
        return try executeResults[index].get()
    }

    func stream(_ endpoint: any Endpoint) async throws -> StreamResponse {
        sentEndpoints.append(endpoint)
        let index = streamCallCount
        streamCallCount += 1
        guard index < streamResults.count else {
            let emptyLines = AsyncThrowingStream<String, Error> { $0.finish() }
            return StreamResponse(statusCode: 200, content: .lines(emptyLines))
        }
        return try streamResults[index].get()
    }
}