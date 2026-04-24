@testable import XcodeAssistantCopilotServer
import Hummingbird
import NIOCore
import Synchronization

final class MockChatCompletion: ChatCompletionProtocol, Sendable {
    private struct State {
        var streamCallCount = 0
        var lastRequest: ChatCompletionRequest?
        var lastCredentials: CopilotCredentials?
        var response: Response = Response(
            status: .ok,
            headers: [:],
            body: .init(asyncSequence: AsyncStream<ByteBuffer> { $0.finish() })
        )
        var responseSequence: [Result<Response, Error>] = []
        var errorToThrow: Error?
    }

    private let state = Mutex(State())

    var streamCallCount: Int { state.withLock { $0.streamCallCount } }
    var lastRequest: ChatCompletionRequest? { state.withLock { $0.lastRequest } }
    var lastCredentials: CopilotCredentials? { state.withLock { $0.lastCredentials } }

    var response: Response {
        get { state.withLock { $0.response } }
        set { state.withLock { $0.response = newValue } }
    }

    var responseSequence: [Result<Response, Error>] {
        get { state.withLock { $0.responseSequence } }
        set { state.withLock { $0.responseSequence = newValue } }
    }

    var errorToThrow: Error? {
        get { state.withLock { $0.errorToThrow } }
        set { state.withLock { $0.errorToThrow = newValue } }
    }

    func streamResponse(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async throws -> Response {
        let result: Result<Response, Error>? = state.withLock {
            $0.streamCallCount += 1
            $0.lastRequest = request
            $0.lastCredentials = credentials
            let index = $0.streamCallCount - 1
            if index < $0.responseSequence.count {
                return $0.responseSequence[index]
            }
            if let error = $0.errorToThrow {
                return .failure(error)
            }
            return nil
        }
        if let result {
            return try result.get()
        }
        return state.withLock { $0.response }
    }
}