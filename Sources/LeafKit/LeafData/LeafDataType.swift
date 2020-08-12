// MARK: LeafDataType Public Definition

/// The concrete instantiable object types for `LeafData`
public enum LeafDataType: UInt8, CaseIterable, Hashable {
    // MARK: Cases
    case bool
    case string
    case int
    case double
    case data
    case dictionary
    case array
    case void
    
    public var description: String { short }
}

// MARK: - Internal Only
extension LeafDataType: LKPrintable {
    internal var short: String {
        switch self {
            case .array      : return "array"
            case .bool       : return "bool"
            case .data       : return "data"
            case .dictionary : return "dictionary"
            case .double     : return "double"
            case .int        : return "int"
            case .string     : return "string"
            case .void       : return "void"
        }
    }
    
    /// Get the casting level for two types
    internal func casts(to type: Self) -> LKDConversion {
        typealias _Map = LKDConverters
        switch self {
            case .array      : return _Map.arrayMaps[type]!.is
            case .bool       : return _Map.boolMaps[type]!.is
            case .data       : return _Map.dataMaps[type]!.is
            case .dictionary : return _Map.dictionaryMaps[type]!.is
            case .double     : return _Map.doubleMaps[type]!.is
            case .int        : return _Map.intMaps[type]!.is
            case .string     : return _Map.stringMaps[type]!.is
            case .void       : return .ambiguous
        }
    }
}
