// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// `LeafDataContainer` provides the tangible storage for concrete Swift values, representations of
/// collections, optional value wrappers, and lazy data generators.
internal indirect enum LeafDataContainer: Equatable, SymbolPrintable {
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
    case optional(_ wrapped: LeafDataContainer?, _ type: LeafDataType)
    
    // Lazy resolvable function
    // Must specify return tuple giving (returnType, invariance)
    case lazy(f: () -> (LeafData),
              returns: LeafDataType,
              invariant: Bool)
    
    // MARK: - LeafSymbol Conformance
    
    // MARK: Properties
    internal var resolved: Bool { true }
    internal var invariant: Bool { !isLazy }
    internal var symbols: Set<String> { .init() }
    internal var isAtomic: Bool { true }
    internal var isExpression: Bool { false }
    internal var isAny: Bool { false }
    internal var isConcrete: Bool { true }
    /// Note: Will *always* return a value - can be force-unwrapped safely
    internal var concreteType: LeafDataType? {
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
            case .lazy(_, let t, _),
                 .optional(_, let t) : return t
        }
    }
    
    internal static let comparable: Set<LeafDataType> = [ .double, .int, .string ]
    internal static let numerics: Set<LeafDataType> = [ .double, .int ]
    internal var isNumeric: Bool { Self.numerics.contains(concreteType!) }
    
    // MARK: Functions
    
    /// Will resolve anything but variant Lazy data (99% of everything), and unwrap optionals
    internal func resolve() -> LeafDataContainer {
        guard invariant else { return self }
        switch self {
            case .lazy(let f, _, _)                 : return f().container
            case .optional(.some(let o), _)         : return o
            case .array(let a)                      :
                let resolved: [LeafData] = a.map {
                    LeafData($0.container.resolve())
                }
                return .array(resolved)
            case .dictionary(let d)                 :
                let resolved: [String: LeafData] = d.mapValues {
                    LeafData($0.container.resolve())
                }
                return .dictionary(resolved)
            default                                 : return self
        }
    }
    
    /// Will serialize anything to a String except Lazy -> Lazy
    internal func serialize() -> String? {
        let c = LeafConfiguration.self
        switch self {
            // Atomic non-containers
            case .bool(let b)        : return c.boolFormatter(b)
            case .int(let i)         : return c.intFormatter(i)
            case .double(let d)      : return c.doubleFormatter(d)
            case .string(let s)      : return c.stringFormatter(s)
            // Data
            case .data(let d)        : return c.dataFormatter(d)
            // Wrapped
            case .optional(let o, _) :
                guard let wrapped = o else { return c.nilFormatter() }
                return wrapped.serialize()
            // Atomic containers
            case .array(let a)       :
                let result = a.map { $0.container.serialize() ?? c.nilFormatter() }
                return c.arrayFormatter(result)
            case .dictionary(let d)  :
                let result = d.mapValues { $0.container.serialize() ?? c.nilFormatter()}
                return c.dictFormatter(result)
            case .lazy(let f, _, _)  :
                guard let result = f() as LeafData?, !result.container.isLazy else {
                    return c.nilFormatter() } // Silently fail lazy -> lazy. a better option would be nice
                return result.container.serialize() ?? c.nilFormatter()
        }
    }
    
    /// Final serialization to a shared buffer
    internal func serialize(buffer: inout ByteBuffer) throws {
        if case .data(let d) = self { buffer.writeBytes(d); return }
        guard let data = serialize()?.data(using: LeafConfiguration.encoding)
            else { throw "Serialization Error" }
        buffer.writeBytes(data)
    }
    
    // MARK: - Equatable Conformance
   
    /// Strict equality comparision, with .nil/.void being equal - will fail on Lazy data that is variant
    internal static func == (lhs: LeafDataContainer, rhs: LeafDataContainer) -> Bool {
        // If both sides are optional and nil, equal
        guard !lhs.isNil || !rhs.isNil else                   { return true }
        // Both sides must be non-nil and same concrete type, or unequal
        guard !lhs.isNil && !rhs.isNil,
              lhs.concreteType == rhs.concreteType else       { return false }
        // As long as both are static types, test them
        if !lhs.isLazy && !rhs.isLazy {
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
        } else if case .lazy(let lhsF, let lhsR, let lhsI) = lhs,
                  case .lazy(let rhsF, let rhsR, let rhsI) = rhs {
            // Only compare lazy equality if invariant to avoid side-effects
            guard lhsI && rhsI, lhsR == rhsR else             { return false }
                                                                return lhsF() == rhsF()
        } else                                                { return false }
    }
    
    // MARK: - CustomStringConvertible
    internal var description: String { short }
    
    internal var short: String {
        switch self {
            case .array(let a)       : return "array(\(a.count))"
            case .bool(let b)        : return "bool(\(b))"
            case .data(let d)        : return "data(\(d.count))"
            case .dictionary(let d)  : return "dictionary(\(d.count))"
            case .double(let d)      : return "double(\(d))"
            case .int(let i)         : return "int(\(i))"
            case .lazy(_, let r, _)  : return "lazy(() -> \(r)?)"
            case .optional(_, let t) : return "\(t)()?"
            case .string(let s)      : return "string(\(s))"
        }
    }
    
    // MARK: - Other
    internal var isNil: Bool {
        switch self {
            case .optional(let o, _) where o == nil : return true
            default                                 : return false
        }
    }
    
    internal var isLazy: Bool {
        if case .lazy = self { return true } else { return false }
    }

    /// Flat mapping behavior - will never re-wrap .optional
    internal var wrap: LeafDataContainer {
        if case .optional = self { return self }
        return .optional(self, concreteType!)
    }
    
    internal var unwrap: LeafDataContainer? {
        guard case .optional(let optional, _) = self else { return self }
        return optional
    }
}
