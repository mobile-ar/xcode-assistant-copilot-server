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
    }

    private let state = Mutex(State())

    var streamCallCount: Int { state.withLock { $0.streamCallCount } }
    var lastRequest: ChatCompletionRequest? { state.withLock { $0.lastRequest } }
    var lastCredentials: CopilotCredentials? { state.withLock { $0.lastCredentials } }

    var response: Response {
        get { state.withLock { $0.response } }
        set { state.withLock { $0.response = newValue } }
    }

    func streamResponse(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async -> Response {
        state.withLock {
            $0.streamCallCount += 1
            $0.lastRequest = request
            $0.lastCredentials = credentials
        }
        return state.withLock { $0.response }
    }
}
