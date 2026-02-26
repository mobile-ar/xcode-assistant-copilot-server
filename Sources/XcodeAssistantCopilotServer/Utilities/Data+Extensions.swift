import Foundation

extension Data {
    var prettyPrintedJSON: String {
        if let jsonObject = try? JSONSerialization.jsonObject(with: self),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return String(data: self, encoding: .utf8) ?? "<non-UTF8 data, \(count) bytes>"
    }
}
