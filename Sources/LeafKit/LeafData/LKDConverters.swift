// MARK: Subject to change prior to 1.0.0 release

import Foundation

// MARK: - Data Converter Static Mapping

/// Stages of convertibility
internal enum LKDConversion: UInt8, Hashable, Comparable {
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
internal enum LKDConverters {
    typealias ArrayMap = (`is`: LKDConversion, via: ([LKD]) -> LKD)
    static let arrayMaps: [LKDT: ArrayMap] = [
        .array      : (is: .identity, via: { .array($0) }),

        .bool       : (is: .coercible, via: { _ in .bool(true) }),
        
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
        .int        : (is: .ambiguous, via: { _ in .trueNil }),
        .string     : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias BoolMap = (`is`: LKDConversion, via: (Bool) -> LKD)
    static let boolMaps: [LKDT: BoolMap] = [
        .bool       : (is: .identity, via: { .bool($0) }),
        
        .double     : (is: .castable, via: { .double($0 ? 1.0 : 0.0) }),
        .int        : (is: .castable, via: { .int($0 ? 1 : 0) }),
        .string     : (is: .castable, via: { .string($0.description) }),

        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias DataMap = (`is`: LKDConversion, via: (Data) -> LKD)
    static let dataMaps: [LKDT: DataMap] = [
        .data       : (is: .identity, via: { .data($0) }),
        
        .bool       : (is: .coercible, via: { _ in .bool(true) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .int        : (is: .ambiguous, via: { _ in .trueNil }),
        .string     : (is: .ambiguous, via: { _ in .trueNil })
    ]
            
    typealias DictionaryMap = (`is`: LKDConversion, via: ([String: LKD]) -> LKD)
    static let dictionaryMaps: [LKDT: DictionaryMap] = [
        .dictionary : (is: .identity, via: { .dictionary($0) }),
        
        .bool       : (is: .coercible, via: { _ in .bool(true) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .double     : (is: .ambiguous, via: { _ in .trueNil }),
        .int        : (is: .ambiguous, via: { _ in .trueNil }),
        .string     : (is: .ambiguous, via: { _ in .trueNil })
    ]
    
    typealias DoubleMap = (`is`: LKDConversion, via: (Double) -> LKD)
    static let doubleMaps: [LKDT: DoubleMap] = [
        .double     : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: { .bool([0.0, 1.0].contains($0) ? $0 == 1.0 : true) }),
        .string     : (is: .castable, via: { .string($0.description) }),
        
        .int        : (is: .coercible, via: { .int(Int(exactly: $0.rounded())) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
    
    typealias IntMap = (`is`: LKDConversion, via: (Int) -> LKD)
    static let intMaps: [LKDT: IntMap] = [
        .int        : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: { .bool([0, 1].contains($0) ? $0 == 1 : true) }),
        .double     : (is: .castable, via: { .double(Double($0)) }),
        .string     : (is: .castable, via: { .string($0.description) }),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
    
    typealias StringMap = (`is`: LKDConversion, via: (String) -> LKD)
    static let stringMaps: [LKDT: StringMap] = [
        .string     : (is: .identity, via: { $0.leafData }),
        
        .bool       : (is: .castable, via: {
                        .bool(LeafKeyword(rawValue: $0.lowercased())?.bool ?? true) }),
        .double     : (is: .castable, via: { .double(Double($0)) }),
        .int        : (is: .castable, via: { .int(Int($0)) } ),
        
        .array      : (is: .ambiguous, via: { _ in .trueNil }),
        .data       : (is: .ambiguous, via: { _ in .trueNil }),
        .dictionary : (is: .ambiguous, via: { _ in .trueNil }),
    ]
}
