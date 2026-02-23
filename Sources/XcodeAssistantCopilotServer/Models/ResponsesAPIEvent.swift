import Foundation

public struct ResponsesTextDeltaEvent: Decodable, Sendable {
    public let delta: String
    public let contentIndex: Int?
    public let outputIndex: Int?

    enum CodingKeys: String, CodingKey {
        case delta
        case contentIndex = "content_index"
        case outputIndex = "output_index"
    }

    public init(delta: String, contentIndex: Int? = nil, outputIndex: Int? = nil) {
        self.delta = delta
        self.contentIndex = contentIndex
        self.outputIndex = outputIndex
    }
}

public struct ResponsesOutputItemAddedEvent: Decodable, Sendable {
    public let outputIndex: Int
    public let item: ResponsesOutputItem

    enum CodingKeys: String, CodingKey {
        case outputIndex = "output_index"
        case item
    }

    public init(outputIndex: Int, item: ResponsesOutputItem) {
        self.outputIndex = outputIndex
        self.item = item
    }
}

public struct ResponsesOutputItem: Decodable, Sendable {
    public let type: String
    public let id: String?
    public let callId: String?
    public let name: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callId = "call_id"
        case name
        case status
    }

    public init(
        type: String,
        id: String? = nil,
        callId: String? = nil,
        name: String? = nil,
        status: String? = nil
    ) {
        self.type = type
        self.id = id
        self.callId = callId
        self.name = name
        self.status = status
    }
}

public struct ResponsesFunctionCallArgsDeltaEvent: Decodable, Sendable {
    public let delta: String
    public let callId: String?
    public let outputIndex: Int?
    public let itemId: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case callId = "call_id"
        case outputIndex = "output_index"
        case itemId = "item_id"
    }

    public init(
        delta: String,
        callId: String? = nil,
        outputIndex: Int? = nil,
        itemId: String? = nil
    ) {
        self.delta = delta
        self.callId = callId
        self.outputIndex = outputIndex
        self.itemId = itemId
    }
}

public struct ResponsesFunctionCallArgsDoneEvent: Decodable, Sendable {
    public let arguments: String
    public let callId: String?
    public let outputIndex: Int?
    public let itemId: String?

    enum CodingKeys: String, CodingKey {
        case arguments
        case callId = "call_id"
        case outputIndex = "output_index"
        case itemId = "item_id"
    }

    public init(
        arguments: String,
        callId: String? = nil,
        outputIndex: Int? = nil,
        itemId: String? = nil
    ) {
        self.arguments = arguments
        self.callId = callId
        self.outputIndex = outputIndex
        self.itemId = itemId
    }
}

public struct ResponsesCompletedEvent: Decodable, Sendable {
    public let response: ResponsesCompletedResponse

    public init(response: ResponsesCompletedResponse) {
        self.response = response
    }
}

public struct ResponsesCompletedResponse: Decodable, Sendable {
    public let id: String
    public let status: String
    public let output: [ResponsesCompletedOutputItem]?

    public init(id: String, status: String, output: [ResponsesCompletedOutputItem]? = nil) {
        self.id = id
        self.status = status
        self.output = output
    }
}

public struct ResponsesCompletedOutputItem: Decodable, Sendable {
    public let type: String
    public let id: String?
    public let callId: String?
    public let name: String?
    public let arguments: String?
    public let content: [ResponsesCompletedContentPart]?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callId = "call_id"
        case name
        case arguments
        case content
    }

    public init(
        type: String,
        id: String? = nil,
        callId: String? = nil,
        name: String? = nil,
        arguments: String? = nil,
        content: [ResponsesCompletedContentPart]? = nil
    ) {
        self.type = type
        self.id = id
        self.callId = callId
        self.name = name
        self.arguments = arguments
        self.content = content
    }
}

public struct ResponsesCompletedContentPart: Decodable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

public enum ResponsesEventType: String, Sendable {
    case responseCreated = "response.created"
    case responseInProgress = "response.in_progress"
    case outputItemAdded = "response.output_item.added"
    case outputItemDone = "response.output_item.done"
    case contentPartAdded = "response.content_part.added"
    case contentPartDone = "response.content_part.done"
    case outputTextDelta = "response.output_text.delta"
    case outputTextDone = "response.output_text.done"
    case functionCallArgumentsDelta = "response.function_call_arguments.delta"
    case functionCallArgumentsDone = "response.function_call_arguments.done"
    case responseCompleted = "response.completed"
    case responseFailed = "response.failed"
    case responseIncomplete = "response.incomplete"
    case reasoningDelta = "response.reasoning.delta"
    case reasoningDone = "response.reasoning.done"
    case reasoningSummaryDelta = "response.reasoning_summary_part.delta"
    case reasoningSummaryDone = "response.reasoning_summary_part.done"
    case reasoningSummaryTextDelta = "response.reasoning_summary_text.delta"
    case reasoningSummaryTextDone = "response.reasoning_summary_text.done"

    static func fromDataType(_ data: String) -> ResponsesEventType? {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        return ResponsesEventType(rawValue: type)
    }
}