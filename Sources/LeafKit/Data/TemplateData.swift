import Foundation

/// TemplateKit's supported serializable data types.
/// - note: This is different from types supported in the AST.
public struct LeafData: Equatable, LeafDataRepresentable, ExpressibleByDictionaryLiteral, ExpressibleByStringLiteral {

    // MARK: Equatable

    /// See `Equatable`.
    public static func ==(lhs: LeafData, rhs: LeafData) -> Bool {
        /// Fuzzy compare
        if lhs.string != nil && lhs.string == rhs.string {
            return true
        } else if lhs.int != nil && lhs.int == rhs.int {
            return true
        } else if lhs.double != nil && lhs.double == rhs.double {
            return true
        } else if lhs.bool != nil && lhs.bool == rhs.bool {
            return true
        }

        /// Strict compare
        switch (lhs.storage, rhs.storage) {
        case (.array(let a), .array(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.data(let a), .data(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    /// Actual storage.
    internal var storage: LeafDataStorage

    /// Creates a new `LeafData`.
    internal init(_ storage: LeafDataStorage) {
        self.storage = storage
    }

    // MARK: Static

    /// Creates a new `LeafData` from a `Bool`.
    public static func bool(_ value: Bool) -> LeafData {
        return .init(.bool(value))
    }

    /// Creates a new `LeafData` from a `String`.
    public static func string(_ value: String) -> LeafData {
        return .init(.string(value))
    }

    /// Creates a new `LeafData` from am `Int`.
    public static func int(_ value: Int) -> LeafData {
        return .init(.int(value))
    }

    /// Creates a new `LeafData` from a `Double`.
    public static func double(_ value: Double) -> LeafData {
        return .init(.double(value))
    }

    /// Creates a new `LeafData` from `Data`.
    public static func data(_ value: Data) -> LeafData {
        return .init(.data(value))
    }

    /// Creates a new `LeafData` from `[String: LeafData]`.
    public static func dictionary(_ value: [String: LeafData]) -> LeafData {
        return .init(.dictionary(value))
    }

    /// Creates a new `LeafData` from `[LeafData]`.
    public static func array(_ value: [LeafData]) -> LeafData {
        return .init(.array(value))
    }

    /// Creates a new `LeafData` from `() -> LeafData`.
    public static func lazy(_ value: @escaping () -> LeafData) -> LeafData {
        return .init(.lazy(value))
    }

    /// Creates a new null `LeafData`.
    public static var null: LeafData {
        return .init(.null)
    }

    // MARK: Literal

    public init(dictionaryLiteral elements: (String, LeafData)...) {
        self = .dictionary(.init(uniqueKeysWithValues: elements))
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    // MARK: Fuzzy

    /// Attempts to convert to `Bool` or returns `nil`.
    public var bool: Bool? {
        switch storage {
        case .int(let i):
            switch i {
            case 1:
                return true
            case 0:
                return false
            default:
                return nil
            }
        case .double(let d):
            switch d {
            case 1:
                return true
            case 0:
                return false
            default:
                return nil
            }
        case .string(let s):
            return Bool(s)
        case .bool(let b):
            return b
        case .lazy(let lazy):
            return lazy().bool
        default:
            return nil
        }
    }

    /// Attempts to convert to `String` or returns `nil`.
    public var string: String? {
        switch storage {
        case .bool(let bool):
            return bool.description
        case .double(let double):
            return double.description
        case .int(let int):
            return int.description
        case .string(let s):
            return s
        case .data(let d):
            return String(data: d, encoding: .utf8)
        case .lazy(let lazy):
            return lazy().string
        default:
            return nil
        }
    }

    /// Attempts to convert to `Int` or returns `nil`.
    public var int: Int? {
        switch storage {
        case .int(let i):
            return i
        case .string(let s):
            return Int(s)
        case .lazy(let lazy):
            return lazy().int
        default:
            return nil
        }
    }

    /// Attempts to convert to `Double` or returns `nil`.
    public var double: Double? {
        switch storage {
        case .int(let i):
            return Double(i)
        case .double(let d):
            return d
        case .string(let s):
            return Double(s)
        case .lazy(let lazy):
            return lazy().double
        default:
            return nil
        }
    }

    /// Attempts to convert to `Data` or returns `nil`.
    public var data: Data? {
        switch storage {
        case .data(let d):
            return d
        case .string(let s):
            return s.data(using: .utf8)
        case .lazy(let lazy):
            return lazy().data
        case .int(let i):
            return i.description.data(using: .utf8)
        case .double(let d):
            return d.description.data(using: .utf8)
        case .array(let arr):
            var data = Data()

            for i in arr {
                switch i {
                case .null: break
                default:
                    guard let u = i.data else {
                        return nil
                    }

                    data += u
                }
            }

            return data
        default:
            return nil
        }
    }
    
    /// Attempts to convert to `[String: LeafData]` or returns `nil`.
    public var dictionary: [String: LeafData]? {
        switch storage {
        case .dictionary(let d):
            return d
        default:
            return nil
        }
    }

    /// Attempts to convert to `[LeafData]` or returns `nil`.
    public var array: [LeafData]? {
        switch storage {
        case .array(let a):
            return a
        default:
            return nil
        }
    }

    /// Returns `true` if the data is `null`.
    public var isNull: Bool {
        switch storage {
        case .null: return true
        default: return false
        }
    }

    // MARK: Convertible

    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return self
    }
}
