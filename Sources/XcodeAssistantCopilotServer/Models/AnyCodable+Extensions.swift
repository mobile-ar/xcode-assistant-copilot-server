import Foundation

extension AnyCodable {
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