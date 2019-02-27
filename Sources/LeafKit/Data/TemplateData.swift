/// TemplateKit's supported serializable data types.
/// - note: This is different from types supported in the AST.
public struct TemplateData: NestedData, Equatable, TemplateDataRepresentable {
    // MARK: Equatable

    /// See `Equatable`.
    public static func ==(lhs: TemplateData, rhs: TemplateData) -> Bool {
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
    internal var storage: TemplateDataStorage

    /// Creates a new `TemplateData`.
    internal init(_ storage: TemplateDataStorage) {
        self.storage = storage
    }

    // MARK: Static

    /// Creates a new `TemplateData` from a `Bool`.
    public static func bool(_ value: Bool) -> TemplateData {
        return .init(.bool(value))
    }

    /// Creates a new `TemplateData` from a `String`.
    public static func string(_ value: String) -> TemplateData {
        return .init(.string(value))
    }

    /// Creates a new `TemplateData` from am `Int`.
    public static func int(_ value: Int) -> TemplateData {
        return .init(.int(value))
    }

    /// Creates a new `TemplateData` from a `Double`.
    public static func double(_ value: Double) -> TemplateData {
        return .init(.double(value))
    }

    /// Creates a new `TemplateData` from `Data`.
    public static func data(_ value: Data) -> TemplateData {
        return .init(.data(value))
    }

    /// Creates a new `TemplateData` from `[String: TemplateData]`.
    public static func dictionary(_ value: [String: TemplateData]) -> TemplateData {
        return .init(.dictionary(value))
    }

    /// Creates a new `TemplateData` from `[TemplateData]`.
    public static func array(_ value: [TemplateData]) -> TemplateData {
        return .init(.array(value))
    }

    /// Creates a new `TemplateData` from `() -> TemplateData`.
    public static func lazy(_ value: @escaping () -> TemplateData) -> TemplateData {
        return .init(.lazy(value))
    }

    /// Creates a new null `TemplateData`.
    public static var null: TemplateData {
        return .init(.null)
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
    
    /// Attempts to convert to `[String: TemplateData]` or returns `nil`.
    public var dictionary: [String: TemplateData]? {
        switch storage {
        case .dictionary(let d):
            return d
        default:
            return nil
        }
    }

    /// Attempts to convert to `[TemplateData]` or returns `nil`.
    public var array: [TemplateData]? {
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

    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return self
    }
}
