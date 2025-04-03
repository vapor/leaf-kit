import Foundation
import NIOCore
import NIOFoundationCompat

// swift-format-ignore
indirect enum LeafDataStorage: Equatable, CustomStringConvertible, Sendable {
    // MARK: - Cases

    // Static values
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case data(Data)

    // Collections
    case dictionary([String: LeafData])
    case array([LeafData])

    // Wrapped `Optional<LeafDataStorage>`
    case optional(_ wrapped: LeafDataStorage?, _ type: LeafData.NaturalType)

    // MARK: Properties

    var concreteType: LeafData.NaturalType {
        switch self {
        // Concrete Types
        case .array:      .array
        case .bool:       .bool
        case .data:       .data
        case .dictionary: .dictionary
        case .double:     .double
        case .int:        .int
        case .string:     .string
        // Optional Types
        case .optional(_, let t): t
        }
    }

    // MARK: Functions

    /// Will resolve anything and unwrap optionals
    func resolve() -> LeafDataStorage {
        return switch self {
        case .optional(let o, _): o ?? self
        case .array(let a):       .array(a.map { .init($0.storage.resolve()) })
        case .dictionary(let d):  .dictionary(d.mapValues { .init($0.storage.resolve()) })
        default:                  self
        }
    }

    /// Serialize anything to a string.
    func serialize() -> String {
        switch self {
        case .bool(let b):        LeafConfiguration.boolFormatter(b)
        case .int(let i):         LeafConfiguration.intFormatter(i)
        case .double(let d):      LeafConfiguration.doubleFormatter(d)
        case .string(let s):      LeafConfiguration.stringFormatter(s)
        case .data(let d):        LeafConfiguration.dataFormatter(d) ?? LeafConfiguration.nilFormatter()
        case .optional(let o, _): o?.serialize() ?? LeafConfiguration.nilFormatter()
        case .array(let a):       LeafConfiguration.arrayFormatter(a.map { $0.storage.serialize() })
        case .dictionary(let d):  LeafConfiguration.dictFormatter(d.mapValues { $0.storage.serialize() })
        }
    }

    /// Final serialization to a shared buffer
    func serialize(buffer: inout ByteBuffer) throws {
        switch self {
        case .bool, .int, .double, .string, .optional, .array, .dictionary:
            try buffer.writeString(self.serialize(), encoding: LeafConfiguration.encoding)
        case .data(let d):
            buffer.writeData(d)
        }
    }

    // MARK: - Equatable Conformance

    /// Strict equality comparision, with nil being equal
    static func == (lhs: LeafDataStorage, rhs: LeafDataStorage) -> Bool {
        switch (lhs, rhs) {
        // Both optional and nil
        case (.optional(nil, _),    .optional(nil, _)):    true
        // Both optional and non-nil
        case (.optional(let l?, _), .optional(let r?, _)): l == r
        // One or the other optional and non-nil, unwrap and compare
        case (.optional(let l?, _), let r),
             (let l, .optional(let r?, _)):                l == r

        // Direct concrete type comparisons
        case (     .array(let l),      .array(let r)):     l == r
        case (.dictionary(let l), .dictionary(let r)):     l == r
        case (      .bool(let l),       .bool(let r)):     l == r
        case (    .string(let l),     .string(let r)):     l == r
        case (       .int(let l),        .int(let r)):     l == r
        case (    .double(let l),     .double(let r)):     l == r
        case (      .data(let l),       .data(let r)):     l == r

        // Any other combo is unequal
        default:                                           false
        }
    }

    // MARK: - CustomStringConvertible
    var description: String {
        switch self {
        case .array(let a):       "array(\(a.count))"
        case .bool(let b):        "bool(\(b))"
        case .data(let d):        "data(\(d.count))"
        case .dictionary(let d):  "dictionary(\(d.count))"
        case .double(let d):      "double(\(d))"
        case .int(let i):         "int(\(i))"
        case .optional(let o, _): "optional(\(o.map { "\($0)" } ?? "nil")))"
        case .string(let s):      "string(\(s))"
        }
    }

    var short: String {
        self.serialize()
    }

    // MARK: - Other
    var isNil: Bool {
        switch self {
        case .optional(.none, _): true
        default: false
        }
    }

    /// Flat mapping behavior, turns non-optional into optional. Will never re-wrap optional.
    var wrap: LeafDataStorage {
        switch self {
        case .optional: self
        default: .optional(self, self.concreteType)
        }
    }

    /// Unwrap storage optional to Swift optional.
    var unwrap: LeafDataStorage? {
        switch self {
        case .optional(let optional, _): optional
        default: self
        }
    }
}
