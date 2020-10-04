import Foundation

/// `LKDContainer` provides the tangible storage for concrete Swift values, representations of
/// collections, optional value wrappers, and lazy data generators.
internal indirect enum LKDContainer: Equatable, LKPrintable {
    // MARK: - Cases
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case data(Data)

    // FIXME: Dictionary & Array should store a bool to signal homogenous/heterogenous
    
    /// `[String: LeafData]`
    case dictionary([String: LKData])
    /// `[LeafData]`
    case array([LKData])

    /// Wrapped `Optional<LDContainer>`
    case optional(_ wrapped: Self?, _ type: LKDType)

    /// Lazy resolvable `() -> LeafData` where return is of `LeafDataType`
    case lazy(f: () -> LeafData, returns: LKDType)

    /// A lazy evaluation of the param - Must be generated *only* during `LKSerialize` to defer evaluation
    case evaluate(param: LKParameter.Container)

    case error(reason: String, function: String)
    case unset
    
    // MARK: - Properties

    /// The LeafDataType the container will evaluate to
    var baseType: LKDType {
        switch self {
            // Concrete Types
            case .array              : return .array
            case .bool               : return .bool
            case .data               : return .data
            case .dictionary         : return .dictionary
            case .double             : return .double
            case .int                : return .int
            case .string             : return .string
            // Internal Wrapped Types
            case .lazy(_, let t),
                 .optional(_, let t) : return t
            case .evaluate           : return .void
            case .error              : return .void
            case .unset              : return .void
        }
    }

    /// Will resolve anything but variant Lazy data (99% of everything), and unwrap optionals
    var evaluate: LKData {
        if case .lazy(let f, _) = self { return f() }
        if self == .unset { return .error(internal: "Variable used before being initialized") }
        return .init(self)
    }

    // MARK: - Equatable Conformance
    /// Strict equality comparision, with .nil/.void being equal - will fail on Lazy data that is variant
    static func ==(lhs: Self, rhs: Self) -> Bool {
        // If either side is optional and nil...
        if lhs.isNil || rhs.isNil                             {
            // Both sides must be nil
            if lhs.isNil != rhs.isNil                         { return false }
            // And concrete type must match
                                         return lhs.baseType == rhs.baseType }
        // Both sides must be invariant or we won't test at all
        guard (lhs.isLazy || rhs.isLazy) == false else        { return false }

        // Direct tests on two concrete values of the same concrete type
        switch (lhs, rhs) {
            // Direct concrete type comparisons
            case (     .array(let a),      .array(let b)) : return a == b
            case (.dictionary(let a), .dictionary(let b)) : return a == b
            case (      .bool(let a),       .bool(let b)) : return a == b
            case (    .string(let a),     .string(let b)) : return a == b
            case (       .int(let a),        .int(let b)) : return a == b
            case (    .double(let a),     .double(let b)) : return a == b
            case (      .data(let a),       .data(let b)) : return a == b
            // Both/one side(s) are optional, unwrap and compare
            case (.optional(.some(let l),_), .optional(.some(let r),_))
                                                          : return l == r
            case (.optional(.some(let l),_),           _) : return l == rhs
            case (          _, .optional(.some(let r),_)) : return r == lhs
            default                                       : return false
        }
    }

    var description: String { short }
    var short: String {
        switch self {
            case .array(let a)       : return "array(count: \(a.count))"
            case .bool(let b)        : return "bool(\(b))"
            case .data(let d)        : return "data(\(d.count.formatBytes())"
            case .dictionary(let d)  : return "dictionary(count: \(d.count))"
            case .double(let d)      : return "double(\(d))"
            case .int(let i)         : return "int(\(i))"
            case .lazy(_, let r)     : return "lazy(() -> \(r)?)"
            case .optional(_, let t) : return "\(t)()?"
            case .string(let s)      : return "string(\(s))"
            case .evaluate           : return "evaluate(deferred)"
            case .error              : return "error(\(self.error!))"
            case .unset              : return "unset"
        }
    }

    // MARK: - Other
    var isOptional: Bool { if case .optional = self { return true } else { return false } }
    var isNil: Bool { if case .optional(nil, _) = self { return true } else { return false } }
    var isLazy: Bool { if case .lazy = self { return true } else { return false } }

    /// Flat mapping behavior - will never re-wrap .optional
    var wrap: Self { isOptional ? self : .optional(self, baseType) }
    var unwrap: Self? { if case .optional(let o, _) = self { return o } else { return self } }
    
    /// Nil if not errored, or errored function/reason
    var error: String? { if case .error(let r, let f) = self { return "\(f): \(r)" } else { return nil } }
    var isUnset: Bool { self == .unset }
    
    
    var state: LKDState {
        var state: LKDState
        if case .error = self { return .error }
        
        switch baseType {
            case .array      : state = .array
            case .bool       : state = .bool
            case .data       : state = .data
            case .dictionary : state = .dictionary
            case .double     : state = .double
            case .int        : state = .int
            case .string     : state = .string
            case .void       : state = .void
        }
        switch self {
            case .lazy               : state.formUnion(.variant)
            case .optional(.none, _) : state.formUnion([.optional, .nil])
            case .optional           : state.formUnion(.optional)
            case .unset              : state.formUnion(.variant)
            default: break
        }
        return state
    }
}

/// Various conveniences for bit ops on LKDContainers
///
/// Note: rawValue of 0 is implicit `Error` type
internal struct LKDState: OptionSet {
    let rawValue: UInt16
    init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Top 4 bits for container case
    static let celfMask = Self(rawValue: 0xF000)
    static let _void = Self(rawValue: 1 << 12)
    static let _bool = Self(rawValue: 2 << 12)
    static let _int = Self(rawValue: 3 << 12)
    static let _double = Self(rawValue: 4 << 12)
    static let _string = Self(rawValue: 5 << 12)
    static let _array = Self(rawValue: 6 << 12)
    static let _dictionary = Self(rawValue: 7 << 12)
    static let _data = Self(rawValue: 8 << 12)

    static let numeric = Self(rawValue: 1 << 0)
    static let comparable = Self(rawValue: 1 << 1)
    static let collection = Self(rawValue: 1 << 2)
    static let variant = Self(rawValue: 1 << 3)
    static let optional = Self(rawValue: 1 << 4)
    static let `nil` = Self(rawValue: 1 << 5)

    static let error: Self = Self(rawValue: 0)
    
    static let void: Self = [_void]
    static let bool: Self = [_bool, comparable]
    static let int: Self = [_int, comparable, numeric]
    static let double: Self = [_double, comparable, numeric]
    static let string: Self = [_string, comparable]
    static let array: Self = [_array, collection]
    static let dictionary: Self = [_dictionary, collection]
    static let data: Self = [_data]
    static let trueNil: Self = [_void, optional, `nil`]
}
