import Foundation

extension AnyCodable {
    var boolValue: Bool? {
        if case .bool(let value) = self.value {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self.value {
            return value
        }
        return nil
    }

    init(fromAny value: Any) {
        switch value {
        case let string as String:
            self = AnyCodable(.string(string))
        case let int as Int:
            self = AnyCodable(.int(int))
        case let double as Double:
            self = AnyCodable(.double(double))
        case let bool as Bool:
            self = AnyCodable(.bool(bool))
        case let array as [Any]:
            self = AnyCodable(.array(array.map { AnyCodable(fromAny: $0) }))
        case let dict as [String: Any]:
            self = AnyCodable(.dictionary(dict.compactMapValues { AnyCodable(fromAny: $0) }))
        default:
            self = AnyCodable(.null)
        }
    }
}