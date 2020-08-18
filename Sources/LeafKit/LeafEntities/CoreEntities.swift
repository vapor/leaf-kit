// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - LeafMethods

/// (Array | Dictionary) -> Int
internal struct CollectionToIntMap: LeafMethod {
    static var callSignature: CallParameters { [.types(.collections)] }
    static var returns: Set<LeafDataType> { [.int] }
    static let invariant: Bool = true

    internal var f: (AnyCollection<LeafData>) -> Int
    init(_ map: @escaping (AnyCollection<LeafData>) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        if params[0].celf == .dictionary, let dict = params[0].dictionary {
            return .int(f(.init(dict.values)))
        } else if params[0].celf == .array, let array = params[0].array {
            return .int(f(.init(array)))
        }
        return .trueNil
    }
}

/// (Array | Dictionary) -> Bool
internal struct CollectionToBoolMap: LeafMethod {
    static var callSignature: CallParameters { [.types(.collections)] }
    static var returns: Set<LeafDataType> { [.bool] }
    static let invariant: Bool = true

    internal var f: (AnyCollection<LeafData>) -> Bool
    init(_ map: @escaping (AnyCollection<LeafData>) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        if params[0].celf == .dictionary, let dict = params[0].dictionary {
            return .bool(f(.init(dict.values)))
        } else if params[0].celf == .array, let array = params[0].array {
            return .bool(f(.init(array)))
        }
        return .trueNil
    }
}

/// (Array | Dictionary, Any) -> Bool
internal struct CollectionElementToBoolMap: LeafMethod {
    static var callSignature: CallParameters { [.types(.collections), .types(.any)] }
    static var returns: Set<LeafDataType> { [.bool] }
    static let invariant: Bool = true

    internal var f: (AnyCollection<LeafData>, LeafData) -> Bool
    init(_ map: @escaping (AnyCollection<LeafData>, LeafData) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        if params[0].celf == .dictionary, let dict = params[0].dictionary {
            return .bool(f(.init(dict.values), params[1]))
        } else if params[0].celf == .array, let array = params[0].array {
            return .bool(f(.init(array), params[1]))
        }
        return .trueNil
    }
}

/// (String) -> String
internal struct StrToStrMap: LeafMethod {
    static var callSignature: CallParameters = [ .types([.string]) ]
    static var returns: Set<LeafDataType> { [.string] }
    static let invariant: Bool = true

    internal var f: (String) -> String
    init(_ map: @escaping (String) -> String) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        .string(f(params[0].string!))
    }
}

/// (String, String) -> Bool
internal struct StrStrToBoolMap: LeafMethod {
    static var callSignature: CallParameters = [ .types([.string]), .types([.string]) ]
    static var returns: Set<LeafDataType> { [.bool] }
    static let invariant: Bool = true

    internal var f: (String, String) -> Bool
    init(_ map: @escaping (String, String) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        .bool(f(params[0].string!, params[1].string!))
    }
}

/// (String) -> Int
internal struct StrToIntMap: LeafMethod {
    static var callSignature: CallParameters = [ .types([.string]) ]
    static var returns: Set<LeafDataType> { [.int] }
    static let invariant: Bool = true

    internal var f: (String) -> Int
    init(_ map: @escaping (String) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        .int(f(params[0].string!))
    }
}

internal struct DictionaryCast: LeafFunction {
    static let callSignature: CallParameters = [.types([.dictionary])]
    static let returns: Set<LeafDataType> = [.dictionary]
    static let invariant: Bool = true

    func evaluate(_ params: CallValues) -> LeafData {
        params[0].celf == .dictionary ? params[0] : .trueNil
    }
}
