import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

enum ErrorResponseBuilder {
    static func build(status: HTTPResponse.Status, type: String = "api_error", message: String) -> Response {
        let body: [String: [String: String]] = [
            "error": [
                "message": message,
                "type": type,
            ],
        ]

        let data = (try? JSONEncoder().encode(body)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}
