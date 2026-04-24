import Hummingbird

protocol ChatCompletionProtocol: Sendable {
    func streamResponse(request: ChatCompletionRequest, credentials: CopilotCredentials, configuration: ServerConfiguration) async -> Response
}
