// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// The concrete instantiable object types for a `LeafData`
public enum LeafDataType: String, CaseIterable, Hashable {
    case bool
    case string
    case int
    case double
    case data
    case dictionary
    case array
    case void
    
    internal func casts(to type: Self) -> DataConvertible {
        let state: DataConvertible?
        switch self {
            case .array: state = _ConverterMap.arrayMaps[type]?.is
            case .bool: state = _ConverterMap.boolMaps[type]?.is
            case .data: state = _ConverterMap.dataMaps[type]?.is
            case .dictionary: state = _ConverterMap.dictionaryMaps[type]?.is
            case .double: state = _ConverterMap.doubleMaps[type]?.is
            case .int: state = _ConverterMap.intMaps[type]?.is
            case .string: state = _ConverterMap.stringMaps[type]?.is
            case .void: state = .ambiguous
        }
        return state ?? .ambiguous
    }
}


/// `LeafData` is a "pseudo-protocol" wrapping the physically storable Swift data types
/// Leaf can use directly
/// - `(Bool, Int, Double, String, Array, Dictionary, Data)` are the inherent root types
///     supported, all of which may also be representable as `Optional` values.
/// - `CaseType` presents these cases plus `Void` as a case for functional `LeafSymbols`
/// - `nil` is creatable, but only within context of a root base type - eg, `.nil(.bool)` == `Bool?`
public struct LeafData: LeafSymbol,
                        Equatable,
                        ExpressibleByDictionaryLiteral,
                        ExpressibleByStringLiteral,
                        ExpressibleByIntegerLiteral,
                        ExpressibleByBooleanLiteral,
                        ExpressibleByArrayLiteral,
                        ExpressibleByFloatLiteral,
                        ExpressibleByNilLiteral {
    
    /// The case-self identity
    public var celf: LeafDataType { container.concreteType! }
    
    /// Returns `true` if the data is `nil` or `void`.
    public var isNil: Bool { container.isNil }
    /// Returns `true` if the data can hold other data - we don't consider `Optional` for this purpose
    public var isCollection: Bool { [.array, .dictionary].contains(container.concreteType!) }
    
    /// Returns `true` if concrete object can be exactly or losslessly cast to a second type
    /// - EG: `.nil ` -> `.string("")`, `.int(1)` ->  `.double(1.0)`,
    ///      `.bool(true)` -> `.string("true")` are all one-way lossless conversions
    /// - This does not imply it's not possible to *coerce* data - handle with `coerce(to:)`
    ///   EG: `.string("")` -> `.nil`, `.string("1")` -> ` .bool(true)`
    public func isCastable(to type: LeafDataType) -> Bool { celf.casts(to: type) >= .castable }
    
    /// Returns `true` if concrete object is potentially directly coercible to a second type in some way
    /// - EG: `.array()` -> `.dictionary()` where array indices become keys
    ///       or `.int(1)` -> `.bool(true)`
    /// - This does *not* validate the data itself in coercion
    public func isCoercible(to type: LeafDataType) -> Bool { celf.casts(to: type) >= .coercible }
    
    // MARK: - Equatable Conformance
    public static func ==(lhs: LeafData, rhs: LeafData) -> Bool {
        // Strict compare of invariant stored values; considers .nil & .void equal
        guard !(lhs.container == rhs.container) else { return true }
        // If either side is nil, false - container == would have returned false
        guard !lhs.isNil && !rhs.isNil else { return false }
        // - Lazy variant data should never be tested due to potential side-effects
        guard lhs.invariant && rhs.invariant else { return false }
        // Fuzzy comparison by string casting
        guard lhs.isCastable(to: .string),
              rhs.isCastable(to: .string),
              let lhs = lhs.string, let rhs = rhs.string else { return false }
        return lhs == rhs
    }
    
    // MARK: - SymbolPrintable
    public var description: String { container.description }
    public var short: String { container.short }
    
    /// Returns `true` if the object has a single uniform type
    /// - Always true for invariant non-containers
    /// - True or false for containers if determinable
    /// - Nil if the object is variant lazy data, or invariant lazy producing a container, or a container holding such
    public var hasUniformType: Bool? {
        // Default case - anything that doesn't return a container
        if !isCollection { return true }
        // A container-returning lazy (unknowable) - specific test to avoid invariant check
        if container.isLazy && isCollection { return nil }
        // A non-lazy container - somewhat expensive to check
        if case .array(let a) = container {
            guard a.count > 1, let first = a.first?.concreteType else { return true }
            return a.allSatisfy { $0.celf == first && $0.hasUniformType ?? false }
        } else if case .dictionary(let d) = container {
            guard d.count > 1, let first = d.values.first?.concreteType else { return true }
            return d.values.allSatisfy { $0.celf == first && $0.hasUniformType ?? false }
        } else { return nil }
    }
    
    /// Returns the uniform type of the object, or nil if it can't be determined/is a non-uniform container
    public var uniformType: LeafDataType? {
        guard let determinable = hasUniformType, determinable else { return nil }
        if !isCollection { return container.concreteType! }
        if case .array(let a) = container {
            return a.isEmpty ? .void : a.first?.concreteType ?? nil
        } else if case .dictionary(let d) = container {
            return d.values.isEmpty ? .void : d.values.first?.concreteType ?? nil
        } else { return nil }
    }
    
    // MARK: - Generic `LeafDataRepresentable` Initializer
    public init(_ leafData: LeafDataRepresentable) { self = leafData.leafData }

    // MARK: - Static Initializer Conformances
    /// Creates a new `LeafData` from a `Bool`.
    public static func bool(_ value: Bool?) -> LeafData {
        value.map { LeafData(.bool($0)) } ?? .nil(.bool)
    }
    /// Creates a new `LeafData` from a `String`.
    public static func string(_ value: String?) -> LeafData {
        value.map { LeafData(.string($0)) } ?? .nil(.string)
    }
    /// Creates a new `LeafData` from am `Int`.
    public static func int(_ value: Int?) -> LeafData {
        value.map { LeafData(.int($0)) } ?? .nil(.int)
    }
    /// Creates a new `LeafData` from a `Double`.
    public static func double(_ value: Double?) -> LeafData {
        value.map { LeafData(.double($0)) } ?? .nil(.double)
    }
    /// Creates a new `LeafData` from `Data`.
    public static func data(_ value: Data?) -> LeafData {
        value.map { LeafData(.data($0)) } ?? .nil(.data)
    }
    /// Creates a new `LeafData` from `[String: LeafData]`.
    public static func dictionary(_ value: [String: LeafData]?) -> LeafData {
        value.map { LeafData(.dictionary($0)) } ?? .nil(.dictionary)
    }
    /// Creates a new `LeafData` from `[LeafData]`.
    public static func array(_ value: [LeafData]?) -> LeafData {
        value.map { LeafData(.array($0)) } ?? .nil(.array)
    }
    /// Creates a new `LeafData` for `Optional<LeafData>`
    public static func `nil`(_ type: LeafDataType) -> LeafData {
        LeafData(.optional(nil, type))
    }

    // MARK: - Literal Initializer Conformances
    public init(nilLiteral: ()) { self = .trueNil }
    public init(stringLiteral value: StringLiteralType) { self = value.leafData }
    public init(integerLiteral value: IntegerLiteralType) { self = value.leafData }
    public init(floatLiteral value: FloatLiteralType) { self = value.leafData }
    public init(booleanLiteral value: BooleanLiteralType) { self = value.leafData }
    public init(arrayLiteral elements: LeafData...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, LeafData)...) {
        self = .dictionary(.init(uniqueKeysWithValues: elements))
    }

    // MARK: - Fuzzy Conversions from Storage to Types

    /// Attempts to convert to `Bool`: if a nil optional Bool, returns `nil` - returns t/f if bool-evaluated.
    /// Anything that is tangible but not evaluable to bool reports on its optional-ness as truth.
    public var bool: Bool? {
        if case .bool(let b) = container { return b }
        guard case .bool(let b) = coerce(to: .bool).container else { return nil }
        return b
    }

    /// Attempts to convert to `String` or returns `nil`.
    public var string: String? {
        if case .string(let s) = container { return s }
        guard case .string(let s) = coerce(to: .string).container else { return nil }
        return s
    }

    /// Attempts to convert to `Int` or returns `nil`.
    public var int: Int? {
        if case .int(let i) = container { return i }
        guard case .int(let i) = coerce(to: .int).container else { return nil }
        return i
    }

    /// Attempts to convert to `Double` or returns `nil`.
    public var double: Double? {
        if case .double(let d) = container { return d }
        guard case .double(let d) = coerce(to: .double).container else { return nil }
        return d
    }

    /// Attempts to convert to `Data` or returns `nil`.
    public var data: Data? {
        if case .data(let d) = container { return d }
        guard case .data(let d) = coerce(to: .data).container else { return nil }
        return d
    }

    /// Attempts to convert to `[String: LeafData]` or returns `nil`.
    public var dictionary: [String: LeafData]? {
        if case .dictionary(let d) = container { return d }
        guard case .dictionary(let d) = coerce(to: .dictionary).container else { return nil }
        return d
    }

    /// Attempts to convert to `[LeafData]` or returns `nil`.
    public var array: [LeafData]? {
        if case .array(let a) = container { return a }
        guard case .array(let a) = coerce(to: .array).container else { return nil }
        return a
    }
    
    /// For convenience, `trueNil` is stored as `.optional(nil, .void)`
    public static var trueNil: LeafData { .nil(.void) }
    
    public func cast(to: LeafDataType) -> LeafData { convert(to: to, .castable) }
    public func coerce(to: LeafDataType) -> LeafData { convert(to: to, .coercible) }
    
    // MARK: - Internal Only
    
    /// Actual storage.
    internal private(set) var container: LeafDataContainer
    
    // MARK: - LeafSymbol Conformance
    internal var resolved: Bool { container.resolved }
    internal var invariant: Bool { container.invariant }
    internal var symbols: Set<LeafVariable> { .init() }
    internal var isAtomic: Bool { true }
    internal var isExpression: Bool { false }
    internal var isConcrete: Bool { false }
    internal var isAny: Bool { true }
    internal var concreteType: LeafDataType? { nil }
    internal func resolve() -> LeafData { LeafData(container.resolve()) }
    
    internal func serialize() throws -> String? { container.serialize() }
    internal func serialize(buffer: inout ByteBuffer) throws {
        try container.serialize(buffer: &buffer)
    }
    
    internal func resolve(_ symbols: SymbolMap = [:]) -> Self { self }
    internal func evaluate(_ symbols: SymbolMap = [:]) -> LeafData {
        if case .lazy(let f, _, _) = container { return f() }
        return self
    }

    /// Creates a new `LeafData`.
    internal init(_ container: LeafDataContainer) { self.container = container }
    
    /// Creates a new `LeafData` from `() -> LeafData` if possible or `nil` if not possible.
    /// `returns` must specify a `CaseType` that the function will return
    internal static func lazy(_ lambda: @escaping () -> LeafData,
                            returns type: LeafDataType,
                            invariant sideEffects: Bool) throws -> LeafData {
        LeafData(.lazy(f: lambda, returns: type, invariant: sideEffects))
    }
    
    /// Try to convert one concrete object to a second type. Special handling for optional converting to bool.
    internal func convert(to output: LeafDataType, _ level: DataConvertible = .castable) -> LeafData {
        guard celf != output && invariant else { return self }
        if celf == .void && output == .bool { return .bool(false) }
        if case .lazy(let f,_,_) = container {
            return celf == output ? f() : f().convert(to: output, level) }
        guard let input = container.unwrap else { return .trueNil }
        switch input {
            case .array(let a)      : let m = _ConverterMap.arrayMaps[output]!
                                      return m.is >= level ? m.via(a) : .trueNil
            case .bool(let b)       : let m = _ConverterMap.boolMaps[output]!
                                      return m.is >= level ? m.via(b) : .trueNil
            case .data(let d)       : let m = _ConverterMap.dataMaps[output]!
                                      return m.is >= level ? m.via(d) : .trueNil
            case .dictionary(let d) : let m = _ConverterMap.dictionaryMaps[output]!
                                      return m.is >= level ? m.via(d) : .trueNil
            case .double(let d)     : let m = _ConverterMap.doubleMaps[output]!
                                      return m.is >= level ? m.via(d) : .trueNil
            case .int(let i)        : let m = _ConverterMap.intMaps[output]!
                                      return m.is >= level ? m.via(i) : .trueNil
            case .string(let s)     : let m = _ConverterMap.stringMaps[output]!
                                      return m.is >= level ? m.via(s) : .trueNil
            default                 : return .trueNil
        }
    }
}

// MARK: - Data Converter Static Mapping

/// Stages of convertibility
internal enum DataConvertible: Int, Equatable, Comparable {
    /// Not implicitly convertible automatically
    case ambiguous = 0
    /// A coercion with a clear meaning in one direction
    case coercible = 1
    /// A conversion with a well-defined bi-directional casting possibility
    case castable = 2
    /// An exact type match; identity
    case identity = 3
    
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Map of functions for converting between concrete, non-nil LeafData
///
/// Purely for pass-through identity, casting, or coercing between the concrete types (Bool, Int, Double,
/// String, Array, Dictionary, Data) and will never attempt to handle optionals, which must *always*
/// be unwrapped to concrete types before being called.
///
/// Converters are guaranteed to be provided non-nil input. Failable converters must return LeafData.trueNil
fileprivate enum _ConverterMap {
    
    
    
    private static let c = LeafConfiguration.self
    
    typealias ArrayMap = (`is`: DataConvertible, via: ([LeafData]) -> LeafData)
    static let arrayMaps: [LeafDataType: ArrayMap] = [
        .array      : (is: .identity, via: { .array($0) }),

        .bool       : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { Dictionary(uniqueKeysWithValues: $0.enumerated().map {(String($0), $1)}).leafData }),
        .int        : (is: .ambiguous, via: { _ in .trueNil }),
        .string     : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias BoolMap = (`is`: DataConvertible, via: (Bool) -> LeafData)
    static let boolMaps: [LeafDataType: BoolMap] = [
        .bool       : (is: .identity, via: { .bool($0) }),
        
        .double     : (is: .castable, via: { .double($0 ? 1.0 : 0.0) }),
        .int        : (is: .castable, via: { .int($0 ? 1 : 0) }),
        .string     : (is: .castable, via: { .string($0.description) }),

        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { .data(c.boolFormatter($0).data(using: c.encoding)) }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias DataMap = (`is`: DataConvertible, via: (Data) -> LeafData)
    static let dataMaps: [LeafDataType: DataMap] = [
        .data       : (is: .identity, via: { .data($0) }),
        
        .string     : (is: .castable, via: { .string(String(data: $0, encoding: c.encoding)) }),
        
        .bool       : (is: .coercible, via: { .bool($0.isEmpty) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .int        : (is: .ambiguous, via: { _ in .trueNil })
    ]
            
    typealias DictionaryMap = (`is`: DataConvertible, via: ([String: LeafData]) -> LeafData)
    static let dictionaryMaps: [LeafDataType: DictionaryMap] = [
        .dictionary : (is: .identity, via: { .dictionary($0) }),
        
        .bool       : (is: .coercible, via: { .bool($0.isEmpty) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .int        : (is: .ambiguous, via: { _ in .trueNil }),
        .string     : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias DoubleMap = (`is`: DataConvertible, via: (Double) -> LeafData)
    static let doubleMaps: [LeafDataType: DoubleMap] = [
        .double     : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: { .bool([0.0, 1.0].contains($0) ? $0 == 1.0 : false) }),
        .string     : (is: .castable, via: { .string($0.description) }),
        
        .int        : (is: .coercible, via: { .int(Int(exactly: $0.rounded())) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { .data(c.doubleFormatter($0).data(using: c.encoding)) }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
    
    typealias IntMap = (`is`: DataConvertible, via: (Int) -> LeafData)
    static let intMaps: [LeafDataType: IntMap] = [
        .int        : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: { .bool([0, 1].contains($0) ? $0 == 1 : false) }),
        .double     : (is: .castable, via: { .double(Double($0)) }),
        .string     : (is: .castable, via: { .string($0.description) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { .data(c.intFormatter($0).data(using: c.encoding)) }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
    
    typealias StringMap = (`is`: DataConvertible, via: (String) -> LeafData)
    static let stringMaps: [LeafDataType: StringMap] = [
        .string     : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: { .bool(Bool($0.lowercased()) ?? true) }),
        .double     : (is: .castable, via: { .double(Double($0)) }),
        .int        : (is: .castable, via: { .int(Int($0)) } ),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { .data(c.stringFormatter($0).data(using: c.encoding)) }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
}
