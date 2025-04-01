#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore

indirect enum LeafDataStorage: Equatable, CustomStringConvertible, Sendable {
    // MARK: - Cases
    
    // Static values
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case data(Data)
    
    // Collections (potentially holding lazy values)
    case dictionary([String: LeafData])
    case array([LeafData])

    // Wrapped `Optional<LeafDataStorage>`
    case optional(_ wrapped: LeafDataStorage?, _ type: LeafData.NaturalType)
    
    // Lazy resolvable function
    // Must specify return tuple giving (returnType, invariance)
    case lazy(
        f: @Sendable () -> (LeafData),
        returns: LeafData.NaturalType,
        invariant: Bool
    )

    // MARK: Properties

    var resolved: Bool {
        true
    }

    var invariant: Bool {
        switch self {
        case .bool(_),
             .data(_),
             .double(_),
             .int(_),
             .string(_):
            return true
        case .lazy(_, _, let invariant):
            return invariant
        case .optional(let o, _):
            return o?.invariant ?? true
        case .array(let a):
            let stored = a.map { $0.storage }.filter { $0.isLazy }
            return stored.allSatisfy { $0.invariant }
        case .dictionary(let d):
            let stored = d.values.map { $0.storage }.filter { $0.isLazy }
            return stored.allSatisfy { $0.invariant }
        }
    }

    var symbols: Set<String> {
        .init()
    }

    var isAtomic: Bool {
        true
    }

    var isExpression: Bool {
        false
    }

    var isAny: Bool {
        false
    }

    var isConcrete: Bool {
        true
    }

    /// Note: Will *always* return a value - can be force-unwrapped safely
    var concreteType: LeafData.NaturalType? {
        switch self {
        // Concrete Types
        case .array(_):      .array
        case .bool(_):       .bool
        case .data(_):       .data
        case .dictionary(_): .dictionary
        case .double(_):     .double
        case .int(_):        .int
        case .string(_):     .string
        // Internal Wrapped Types
        case .lazy(_, let t, _),
             .optional(_, let t): t
        }
    }
    
    var isNumeric: Bool {
        Self.numerics.contains(self.concreteType!)
    }

    static let comparable: Set<LeafData.NaturalType> = [
        .double, .int, .string
    ]
    
    static let numerics: Set<LeafData.NaturalType> = [
        .double, .int
    ]

    // MARK: Functions

    /// Will resolve anything but variant Lazy data (99% of everything), and unwrap optionals
    func resolve() -> LeafDataStorage {
        guard self.invariant else {
            return self
        }

        switch self {
        case .lazy(let f, _, _):
            return f().storage
        case .optional(let o, _):
            return o ?? self
        case .array(let a):
            let resolved: [LeafData] = a.map {
                LeafData($0.storage.resolve())
            }
            return .array(resolved)
        case .dictionary(let d):
            let resolved: [String: LeafData] = d.mapValues {
                LeafData($0.storage.resolve())
            }
            return .dictionary(resolved)
        default:
            return self
        }
    }

    /// Will serialize anything to a String except Lazy -> Lazy
    func serialize() throws -> String? {
        let c = LeafConfiguration.self
        switch self {
            // Atomic non-containers
            case .bool(let b):
                return c.boolFormatter(b)
            case .int(let i):
                return c.intFormatter(i)
            case .double(let d):
                return c.doubleFormatter(d)
            case .string(let s):
                return c.stringFormatter(s)
            // Data
            case .data(let d):
                return c.dataFormatter(d)
            // Wrapped
            case .optional(let o, _) :
                guard let wrapped = o else {
                    return c.nilFormatter()
                }
                return try wrapped.serialize()
            // Atomic containers
            case .array(let a)       :
                let result = try a.map { try $0.storage.serialize() ?? c.nilFormatter() }
                return c.arrayFormatter(result)
            case .dictionary(let d)  :
                let result = try d.mapValues { try $0.storage.serialize() ?? c.nilFormatter() }
                return c.dictFormatter(result)
            case .lazy(let f, _, _)  :
                guard let result = f() as LeafData?,
                      !result.storage.isLazy
                else {
                    // Silently fail lazy -> lazy... a better option would be nice
                    return c.nilFormatter()
                }
                return try result.storage.serialize() ?? c.nilFormatter()
        }
    }
    
    /// Final serialization to a shared buffer
    func serialize(buffer: inout ByteBuffer) throws {
        let encoding = LeafConfiguration.encoding
        var data: Data? = nil

        switch self {
        case .bool(_),
             .int(_),
             .double(_),
             .string(_),
             .lazy(_,_,_),
             .optional(_,_),
             .array(_),
             .dictionary(_):
            data = try serialize()!.data(using: encoding)
        case .data(let d):
            data = d
        }
        guard let validData = data else {
            throw "Serialization Error"
        }
        buffer.writeBytes(validData)
    }
    
    // MARK: - Equatable Conformance
   
    /// Strict equality comparision, with .nil/.void being equal - will fail on Lazy data that is variant
    static func == (lhs: LeafDataStorage, rhs: LeafDataStorage) -> Bool {
        // If both sides are optional and nil, equal
        guard !lhs.isNil || !rhs.isNil else {
            return true
        }
        // Both sides must be non-nil and same concrete type, or unequal
        guard !lhs.isNil, !rhs.isNil,
              lhs.concreteType == rhs.concreteType
        else {
            return false
        }
        // As long as both are static types, test them
        if !lhs.isLazy, !rhs.isLazy {
            switch (lhs, rhs) {
                // Direct concrete type comparisons
                case (     .array(let a),      .array(let b)): return a == b
                case (.dictionary(let a), .dictionary(let b)): return a == b
                case (      .bool(let a),       .bool(let b)): return a == b
                case (    .string(let a),     .string(let b)): return a == b
                case (       .int(let a),        .int(let b)): return a == b
                case (    .double(let a),     .double(let b)): return a == b
                case (      .data(let a),       .data(let b)): return a == b
                // Both sides are optional, unwrap and compare
                case (.optional(let l?, _), .optional(let r?, _)):
                    return l == r
                // ... or unwrap just one side
                case (.optional(let l?, _),                _):
                    return l == rhs
                case (                _, .optional(let r?, _)):
                    return r == lhs
                default:
                    return false
            }
        } else if case .lazy(let lhsF, let lhsR, let lhsI) = lhs,
                  case .lazy(let rhsF, let rhsR, let rhsI) = rhs
        {
            // Only compare lazy equality if invariant to avoid side-effects
            guard lhsI, rhsI, lhsR == rhsR else {
                return false
            }
            return lhsF() == rhsF()
        } else {
            return false
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
            case .lazy(_, let r, _):  "lazy(() -> \(r)?)"
            case .optional(_, let t): "\(t)()?"
            case .string(let s):      "string(\(s))"
        }
    }
    
    var short: String {
        (try? self.serialize()) ?? ""
    }

    // MARK: - Other
    var isNil: Bool {
        switch self {
        case .optional(.none, _): true
        default: false
        }
    }
    
    var isLazy: Bool {
        if case .lazy(_, _, _) = self {
            true
        } else {
            false
        }
    }

    /// Flat mapping behavior - will never re-wrap .optional
    var wrap: LeafDataStorage {
        if case .optional(_, _) = self {
            return self
        }
        return .optional(self, concreteType!)
    }
    
    var unwrap: LeafDataStorage? {
        guard case .optional(let optional, _) = self else {
            return self
        }
        return optional
    }
}
