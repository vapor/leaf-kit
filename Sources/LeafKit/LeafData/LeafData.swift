import NIO
import Foundation

/// `LeafData` is a "pseudo-protocol" wrapping the physically storable Swift data types
/// Leaf can use directly
/// - `(Bool, Int, Double, String, Array, Dictionary, Data)` are the inherent root types
///     supported, all of which may also be representable as `Optional` values.
/// - `NaturalType` presents these cases plus `Void` as a case for functional `LeafSymbols`
/// - `nil` is creatable, but only within context of a root base type - eg, `.nil(.bool)` == `Bool?`
public struct LeafData: CustomStringConvertible,
                        Equatable,
                        ExpressibleByDictionaryLiteral,
                        ExpressibleByStringLiteral,
                        ExpressibleByIntegerLiteral,
                        ExpressibleByBooleanLiteral,
                        ExpressibleByArrayLiteral,
                        ExpressibleByFloatLiteral,
                        ExpressibleByNilLiteral,
                        Sendable {

    /// The concrete instantiable object types for a `LeafData`
    public enum NaturalType: String, CaseIterable, Hashable, Sendable {
        case bool
        case string
        case int
        case double
        case data
        case dictionary
        case array
        case void
    }
    /// The case-self identity
    public var celf: NaturalType { storage.concreteType! }
    
    /// Returns `true` if the data is `nil` or `void`.
    public var isNil: Bool { storage.isNil }
    /// Returns `true` if the data can hold other data - we don't consider `Optional` for this purpose
    public var isCollection: Bool { [.array, .dictionary].contains(storage.concreteType) }
    
    /// Returns `true` if concrete object can be exactly or losslessly cast to a second type
    /// - EG: `.nil ` -> `.string("")`, `.int(1)` ->  `.double(1.0)`,
    ///      `.bool(true)` -> `.string("true")` are all one-way lossless conversions
    /// - This does not imply it's not possible to *coerce* data - handle with `coerce(to:)`
    ///   EG: `.string("")` -> `.nil`, `.string("1")` -> ` .bool(true)`
    public func isCastable(to type: LeafData.NaturalType) -> Bool {
        let conversion = _ConverterMap.symbols.get(storage.concreteType!, type)!
        return conversion.is >= DataConvertible.castable
    }
    
    /// Returns `true` if concrete object is potentially directly coercible to a second type in some way
    /// - EG: `.array()` -> `.dictionary()` where array indices become keys
    ///       or `.int(1)` -> `.bool(true)`
    /// - This does *not* validate the data itself in coercion
    public func isCoercible(to type: LeafData.NaturalType) -> Bool {
        let conversion = _ConverterMap.symbols.get(storage.concreteType!, type)!
        return conversion.is >= DataConvertible.coercible
    }
    
    // MARK: - Equatable Conformance
    public static func ==(lhs: LeafData, rhs: LeafData) -> Bool {
        // Strict compare of invariant stored values; considers .nil & .void equal
        guard !(lhs.storage == rhs.storage) else { return true }
        // If either side is nil, false - storage == would have returned false
        guard !lhs.isNil && !rhs.isNil else { return false }
        // - Lazy variant data should never be tested due to potential side-effects
        guard lhs.invariant && rhs.invariant else { return false }
        // Fuzzy comparison by string casting
        guard lhs.isCastable(to: .string),
              rhs.isCastable(to: .string),
              let lhs = lhs.string, let rhs = rhs.string else { return false }
        return lhs == rhs
    }
    
    // MARK: - CustomStringConvertible
    public var description: String { storage.description }
    public var short: String { storage.short }
    
    /// Returns `true` if the object has a single uniform type
    /// - Always true for invariant non-containers
    /// - True or false for containers if determinable
    /// - Nil if the object is variant lazy data, or invariant lazy producing a container, or a container holding such
    public var hasUniformType: Bool? {
        // Default case - anything that doesn't return a container
        if !isCollection { return true }
        // A container-returning lazy (unknowable) - specific test to avoid invariant check
        if storage.isLazy && isCollection { return nil }
        // A non-lazy container - somewhat expensive to check
        if case .array(let a) = storage {
            guard a.count > 1, let first = a.first?.concreteType else { return true }
            return a.allSatisfy { $0.celf == first && $0.hasUniformType ?? false }
        } else if case .dictionary(let d) = storage {
            guard d.count > 1, let first = d.values.first?.concreteType else { return true }
            return d.values.allSatisfy { $0.celf == first && $0.hasUniformType ?? false }
        } else { return nil }
    }
    
    /// Returns the uniform type of the object, or nil if it can't be determined/is a non-uniform container
    public var uniformType: NaturalType? {
        guard let determinable = hasUniformType, determinable else { return nil }
        if !isCollection { return storage.concreteType }
        if case .array(let a) = storage {
            return a.isEmpty ? .void : a.first?.concreteType ?? nil
        } else if case .dictionary(let d) = storage {
            return d.values.isEmpty ? .void : d.values.first?.concreteType ?? nil
        } else { return nil }
    }
    
    // MARK: - Generic `LeafDataRepresentable` Initializer
    public init(_ leafData: LeafDataRepresentable) { self = leafData.leafData }

    // MARK: - Static Initializer Conformances
    /// Creates a new `LeafData` from a `Bool`.
    public static func bool(_ value: Bool?) -> LeafData {
        return value.map { LeafData(.bool($0)) } ?? LeafData(.optional(nil, .bool))
    }
    /// Creates a new `LeafData` from a `String`.
    public static func string(_ value: String?) -> LeafData {
        return value.map { LeafData(.string($0)) } ?? LeafData(.optional(nil, .string))
    }
    /// Creates a new `LeafData` from am `Int`.
    public static func int(_ value: Int?) -> LeafData {
        return value.map { LeafData(.int($0)) } ?? LeafData(.optional(nil, .int))
    }
    /// Creates a new `LeafData` from a `Double`.
    public static func double(_ value: Double?) -> LeafData {
        return value.map { LeafData(.double($0)) } ?? LeafData(.optional(nil, .double))
    }
    /// Creates a new `LeafData` from `Data`.
    public static func data(_ value: Data?) -> LeafData {
        return value.map { LeafData(.data($0)) } ?? LeafData(.optional(nil, .data))
    }
    /// Creates a new `LeafData` from `[String: LeafData]`.
    public static func dictionary(_ value: [String: LeafData]?) -> LeafData {
        return value.map { LeafData(.dictionary($0)) } ?? LeafData(.optional(nil, .dictionary))
    }
    /// Creates a new `LeafData` from `[LeafData]`.
    public static func array(_ value: [LeafData]?) -> LeafData {
        return value.map { LeafData(.array($0)) } ?? LeafData(.optional(nil, .array))
    }
    /// Creates a new `LeafData` for `Optional<LeafData>`
    public static func `nil`(_ type: LeafData.NaturalType) -> LeafData {
        return .init(.optional(nil, type))
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

    /// Attempts to convert to `Bool` or returns `nil`.
    public var bool: Bool? {
        if case .bool(let b) = storage  { return b }
        guard case .bool(let b) = convert(to: .bool).storage else { return nil }
        return b
    }

    /// Attempts to convert to `String` or returns `nil`.
    public var string: String? {
        if case .string(let s) = storage  { return s }
        guard case .string(let s) = convert(to: .string).storage else { return nil }
        return s
    }

    /// Attempts to convert to `Int` or returns `nil`.
    public var int: Int? {
        if case .int(let i) = storage  { return i }
        guard case .int(let i) = convert(to: .int).storage else { return nil }
        return i
    }

    /// Attempts to convert to `Double` or returns `nil`.
    public var double: Double? {
        if case .double(let d) = storage  { return d }
        guard case .double(let d) = convert(to: .double).storage else { return nil }
        return d
    }

    /// Attempts to convert to `Data` or returns `nil`.
    public var data: Data? {
        if case .data(let d) = storage  { return d }
        guard case .data(let d) = convert(to: .data).storage else { return nil }
        return d
    }

    /// Attempts to convert to `[String: LeafData]` or returns `nil`.
    public var dictionary: [String: LeafData]? {
        if case .dictionary(let d) = storage  { return d }
        guard case .dictionary(let d) = convert(to: .dictionary).storage else { return nil }
        return d
    }

    /// Attempts to convert to `[LeafData]` or returns `nil`.
    public var array: [LeafData]? {
        if case .array(let a) = storage  { return a }
        guard case .array(let a) = convert(to: .array).storage else { return nil }
        return a
    }
    
    /// For convenience, `trueNil` is stored as `.optional(nil, .void)`
    public static var trueNil: LeafData { .init(.optional(nil, .void)) }
    
    public func cast(to: LeafData.NaturalType) -> LeafData { convert(to: to, .castable) }
    public func coerce(to: LeafData.NaturalType) -> LeafData { convert(to: to, .coercible) }
    
    // MARK: - Internal Only
    
    /// Actual storage.
    internal private(set) var storage: LeafDataStorage
    
    // MARK: - LeafSymbol Conformance
    internal var resolved: Bool { storage.resolved }
    internal var invariant: Bool { storage.invariant }
    internal var symbols: Set<String> { .init() }
    internal var isAtomic: Bool { true }
    internal var isExpression: Bool { false }
    internal var isConcrete: Bool { false }
    internal var isAny: Bool { true }
    internal var concreteType: NaturalType? { nil }
    internal func resolve() -> LeafData {
        LeafData(storage.resolve())
    }
    internal func serialize() throws -> String? {
        try storage.serialize()
    }
    internal func serialize(buffer: inout ByteBuffer) throws {
        try storage.serialize(buffer: &buffer)
    }
    
    // Hard resolve data (remove invariants), remaining optional if nil
    internal var evaluate: LeafData {
        if case .lazy(let f, _, _) = self.storage { return f() }
        if case .dictionary(let d) = self.storage {
            return .dictionary(d.mapValues { $0.evaluate })
        }
        if case .array(let a) = self.storage {
            return .array(a.map { $0.evaluate })
        }
        return self
    }

    /// Creates a new `LeafData`.
    internal init(_ storage: LeafDataStorage) { self.storage = storage }
    
    /// Creates a new `LeafData` from `() -> LeafData` if possible or `nil` if not possible.
    /// `returns` must specify a `NaturalType` that the function will return
    internal static func lazy(_ lambda: @Sendable @escaping () -> LeafData,
                            returns type: LeafData.NaturalType,
                            invariant sideEffects: Bool) throws -> LeafData {
        LeafData(.lazy(f: lambda, returns: type, invariant: sideEffects))
    }
    
    /// Try to convert one concrete object to a second type.
    internal func convert(to output: NaturalType, _ level: DataConvertible = .castable) -> LeafData {
        guard celf != output else  { return self }
        if case .lazy(let f,_,_) = self.storage { return f().convert(to: output, level) }
        guard let input = storage.unwrap,
              let conversion = _ConverterMap.symbols.get(input.concreteType!, output),
              conversion.is >= level else { return nil }
        switch input {
            case .array(let any as Any),
                 .bool(let any as Any),
                 .data(let any as Any),
                 .dictionary(let any as Any),
                 .double(let any as Any),
                 .int(let any as Any),
                 .string(let any as Any): return conversion.via(any)
            default: return nil
        }
    }

    /// Return a HTML-escaped version of this data if it can be converted to a string.
    internal func htmlEscaped() -> LeafData {
        guard let string = string else {
            return self
        }

        return string.htmlEscaped().leafData
    }
}

// MARK: - Data Converter Static Mapping

/// Stages of convertibility
internal enum DataConvertible: Int, Equatable, Comparable {
    /// Not implicitly convertible automatically
    case ambiguous = 0
    /// A coercioni with a clear meaning in one direction
    case coercible = 1
    /// A conversion with a well-defined bi-directional casting possibility
    case castable = 2
    /// An exact type match; identity
    case identity = 3
    
    static func < (lhs: DataConvertible, rhs: DataConvertible) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Wrapper for associating types and conversion tuple
fileprivate struct Converter: Equatable, Hashable {
    typealias Conversion = (is: DataConvertible, via: (Any) -> LeafData)
    
    let from: LeafData.NaturalType
    let to: LeafData.NaturalType
    let conversion: Conversion?
    
    static func == (lhs: Converter, rhs: Converter) -> Bool {
        (lhs.from == rhs.from) && (lhs.to == rhs.to)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(from)
        hasher.combine(to)
    }
    
    /// Full initializer
    init(_ from: LeafData.NaturalType, _ to: LeafData.NaturalType,
         `is`: DataConvertible, via: @escaping (Any) -> LeafData) {
        self.from = from
        self.to = to
        self.conversion = (`is`, via)
    }
    
    /// Initializer for the "key" only
    init(_ from: LeafData.NaturalType, _ to: LeafData.NaturalType) {
        self.from = from
        self.to = to
        self.conversion = nil
    }
}

fileprivate extension Set where Element == Converter {
    func get(_ from: LeafData.NaturalType, _ to: LeafData.NaturalType) -> Converter.Conversion? {
        self.first(where: { $0 == .init(from, to) })?.conversion
    }
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
    fileprivate static var symbols: Set<Converter> { [
        // MARK: - .identity (Passthrough)
        Converter(.array     , .array     , is: .identity, via: { .array($0 as? [LeafData]) }),
        Converter(.bool      , .bool      , is: .identity, via: { .bool($0 as? Bool) }),
        Converter(.data      , .data      , is: .identity, via: { .data($0 as? Data) }),
        Converter(.dictionary, .dictionary, is: .identity, via: { .dictionary($0 as? [String : LeafData]) }),
        Converter(.double    , .double    , is: .identity, via: { .double($0 as? Double) }),
        Converter(.int       , .int       , is: .identity, via: { .int($0 as? Int) }),
        Converter(.string    , .string    , is: .identity, via: { .string($0 as? String) }),

        // MARK: - .castable (Well-defined bi-directional conversions)
                                        // Double in [0,1] == truthiness & value
        Converter(.double  , .bool         , is: .castable, via: {
            ($0 as? Double).map { [0.0, 1.0].contains($0) ? $0 == 1.0 : nil}?
                .map { .bool($0) } ?? .trueNil
        }),
                                        // Int in [0,1] == truthiness & value
        Converter(.int     , .bool         , is: .castable, via: {
            ($0 as? Int).map { [0, 1].contains($0) ? $0 == 1 : nil }?
                .map { .bool($0) } ?? .trueNil
        }),
                                        //  String == "true" || "false"
        Converter(.string  , .bool         , is: .castable, via: {
            ($0 as? String).map { Bool($0) }?.map { .bool($0) } ?? .trueNil
        }),
                                        // True = 1; False = 0
        Converter(.bool    , .double       , is: .castable, via: {
            ($0 as? Bool).map { $0 ? 1.0 : 0.0 }.map { .double($0) } ?? .trueNil
        }),
                                        // Direct conversion
        Converter(.int     , .double       , is: .castable, via: {
            ($0 as? Int).map { Double($0) }.map { .double($0) } ?? .trueNil
        }),
                                        // Using default string-init
        Converter(.string  , .double       , is: .castable, via: {
            ($0 as? String).map { Double($0) }?.map { .double($0) } ?? .trueNil
        }),
                                        // True = 1; False = 0
        Converter(.bool    , .int          , is: .castable, via: {
            ($0 as? Bool).map { $0 ? 1 : 0 }.map { .int($0) } ?? .trueNil
        }),
                                        // Base10 formatted Strings
        Converter(.string  , .int          , is: .castable, via: {
            ($0 as? String).map { Int($0) }?.map { .int($0) } ?? .trueNil
        }),
                                        // .description
        Converter(.bool    , .string       , is: .castable, via: {
            ($0 as? Bool).map { $0.description }.map { .string($0) } ?? .trueNil
        }),
                                        // Using configured encoding
        Converter(.data    , .string       , is: .castable, via: {
            ($0 as? Data).map { String(data: $0, encoding: c.encoding) }?
                .map { .string($0) } ?? .trueNil
        }),
                                        // .description
        Converter(.double  , .string       , is: .castable, via: {
            ($0 as? Double).map { $0.description }.map { .string($0) } ?? .trueNil
        }),
                                        // .description
        Converter(.int     , .string       , is: .castable, via: {
            ($0 as? Int).map { $0.description }.map { .string($0) } ?? .trueNil
        }),
        
        // MARK: - .coercible (One-direction defined conversion)

                                          // Array.isEmpty == truthiness
        Converter(.array      , .bool       , is: .coercible, via: {
            ($0 as? [LeafData]).map { $0.isEmpty }.map { .bool($0) } ?? .trueNil
        }),
                                          // Data.isEmpty == truthiness
        Converter(.data       , .bool       , is: .coercible, via: {
            ($0 as? Data).map { $0.isEmpty }.map { .bool($0) } ?? .trueNil
        }),
                                          // Dictionary.isEmpty == truthiness
        Converter(.dictionary , .bool       , is: .coercible, via: {
            ($0 as? [String: LeafData]).map { $0.isEmpty }.map { .bool($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.array      , .data       , is: .coercible, via: {
            ($0 as? [LeafData]).map {
                try? LeafDataStorage.array($0).serialize()?.data(using: c.encoding)
            }?.map { .data($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.bool       , .data       , is: .coercible, via: {
            ($0 as? Bool).map { c.boolFormatter($0).data(using: c.encoding) }?
                .map { .data($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.dictionary , .data       , is: .coercible, via: {
            ($0 as? [String: LeafData]).map {
                try? LeafDataStorage.dictionary($0).serialize()?.data(using: c.encoding)
            }?.map { .data($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.double     , .data       , is: .coercible, via: {
            ($0 as? Double).map {
                c.doubleFormatter($0)
                    .data(using: c.encoding)
                }?.map { .data($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.int        , .data       , is: .coercible, via: {
            ($0 as? Int).map { c.intFormatter($0)
                .data(using: c.encoding)
            }?.map { .data($0) } ?? .trueNil
        }),
                                          // Use the configured formatter
        Converter(.string     , .data       , is: .coercible, via: {
            ($0 as? String).map { c.stringFormatter($0)
                .data(using: c.encoding)
            }?.map { .data($0) } ?? .trueNil
        }),
                                          // Schoolbook rounding
        Converter(.double     , .int        , is: .coercible, via: {
            ($0 as? Double).map { Int(exactly: $0.rounded()) }?.map { .int($0) } ?? .trueNil
        }),
        
                                          // Transform with array indices as keys
        Converter(.array      , .dictionary , is: .ambiguous, via: {
            ($0 as? [LeafData]).map {
                Dictionary(uniqueKeysWithValues: $0.enumerated().map {
                                                  (String($0), $1) }) }
                .map { .dictionary($0) } ?? .trueNil
        }),
                                          // Conversion using the formatter
        Converter(.array      , .string     , is: .ambiguous, via: {
            ($0 as? [LeafData]).map {
                let stringified: String? = try? LeafData.array($0).serialize()
                return .string(stringified)
            } ?? .trueNil
        }),
                                          // Conversion using the formatter
        Converter(.dictionary , .string     , is: .ambiguous, via: {
            ($0 as? [String: LeafData]).map {
        let stringified: String? = try? LeafData.dictionary($0).serialize()
                return .string(stringified)
            } ?? .trueNil
        }),

        // MARK: - .ambiguous (Unconvertible)
        Converter(.bool      , .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.data      , .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.dictionary, .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.double    , .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.int       , .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.string    , .array,      is: .ambiguous, via: { _ in nil }),
        Converter(.bool      , .dictionary, is: .ambiguous, via: { _ in nil }),
        Converter(.data      , .dictionary, is: .ambiguous, via: { _ in nil }),
        Converter(.double    , .dictionary, is: .ambiguous, via: { _ in nil }),
        Converter(.int       , .dictionary, is: .ambiguous, via: { _ in nil }),
        Converter(.string    , .dictionary, is: .ambiguous, via: { _ in nil }),
        Converter(.array     , .double,     is: .ambiguous, via: { _ in nil }),
        Converter(.data      , .double,     is: .ambiguous, via: { _ in nil }),
        Converter(.dictionary, .double,     is: .ambiguous, via: { _ in nil }),
        Converter(.array     , .int,        is: .ambiguous, via: { _ in nil }),
        Converter(.data      , .int,        is: .ambiguous, via: { _ in nil }),
        Converter(.dictionary, .int,        is: .ambiguous, via: { _ in nil }),
    ] }
}
