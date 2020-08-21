// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - LeafMethods

/// (Array || Dictionary.values) -> Int
internal struct CollectionToIntMap: LeafMethod {
    static let callSignature: CallParameters = [.types(.collections)]
    static let returns: Set<LeafDataType> = [.int]
    static let invariant: Bool = true
    static let mutating: Bool = false

    init(_ map: @escaping (AnyCollection<LeafData>) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        switch params[0].container {
            case .dictionary(let x) : return .int(f(.init(x.values)))
            case .array(let x)      : return .int(f(.init(x)))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LeafData>) -> Int
    
    static let count: Self = .init({ $0.count })
}

/// (Array || Dictionary.values) -> Bool
internal struct CollectionToBoolMap: LeafMethod {
    static let callSignature: CallParameters = [.types(.collections)]
    static let returns: Set<LeafDataType> = [.bool]
    static let invariant: Bool = true
    static let mutating: Bool = false

    init(_ map: @escaping (AnyCollection<LeafData>) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        switch params[0].container {
            case .dictionary(let x) : return .bool(f(.init(x.values)))
            case .array(let x)      : return .bool(f(.init(x)))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LeafData>) -> Bool
    
    static let isEmpty: Self = .init({ $0.isEmpty })
}

/// (Array | Dictionary, Any) -> Bool
internal struct CollectionElementToBoolMap: LeafMethod {
    static let callSignature: CallParameters = [.types(.collections), .types(.any)]
    static let returns: Set<LeafDataType> = [.bool]
    static let invariant: Bool = true
    static let mutating: Bool = false

    init(_ map: @escaping (AnyCollection<LeafData>, LeafData) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LeafData {
        switch params[0].container {
            case .dictionary(let x) : return .bool(f(.init(x.values), params[1]))
            case .array(let x)      : return .bool(f(.init(x), params[1]))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LeafData>, LeafData) -> Bool
    
    static let contains: Self = .init({for x in $0 where x.celf == $1.celf {if x == $1 { return true }}; return false})
}

/// (String) -> String
internal struct StrToStrMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string])]
    static let returns: Set<LeafDataType> = [.string]
    static let invariant: Bool = true
    static let mutating: Bool = false

    func evaluate(_ params: CallValues) -> LeafData { .string(f(params[0].string!)) }
    
    private init(_ map: @escaping (String) -> String) { f = map }
    private let f: (String) -> String
    
    static let uppercased: Self = .init({ $0.uppercased() })
    static let lowercased: Self = .init({ $0.lowercased() })
    static let escapeHTML: Self = .init({ $0.reduce(into: "", {$0.append(basicHTML[$1] ?? $1.description)}) })
    
    private static let basicHTML: [Character: String] = [
        .lessThan: "&lt;", .greaterThan: "&gt;", .ampersand: "&amp;", .quote: "&quot;", .apostrophe: "&apos;"]
}

/// (String, String) -> String
internal struct StrStrToStrMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string]), .types([.string])]
    static let returns: Set<LeafDataType> = [.string]
    static let invariant: Bool = true
    static let mutating: Bool = false

    func evaluate(_ params: CallValues) -> LeafData { .string(f(params[0].string!, params[1].string!)) }
    
    private init(_ map: @escaping (String, String) -> String) { f = map }
    private let f: (String, String) -> String
}

/// Mutating (String, String)
internal struct MutatingStrStrMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string]), .types([.string])]
    static let returns: Set<LeafDataType> = [.void]
    static let invariant: Bool = true
    static let mutating: Bool = true

    func evaluate(_ params: CallValues) -> LeafData { __MajorBug("Mutating method") }
    func mutatingEvaluate(_ params: CallValues) -> (mutate: LeafData?, result: LeafData) {
        let cache = params[0].string!
        var operand = cache
        f(&operand, params[1].string!)
        return (operand != cache ? operand.leafData : nil, .trueNil)
    }
    
    private init(_ map: @escaping (inout String, String) -> ()) { f = map }
    private let f: (inout String, String) -> ()
    
    static let append: Self = .init({$0.append($1)})
}

/// Mutating (String, Int) -> String
internal struct MutatingStrToStrMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string])]
    static let returns: Set<LeafDataType> = [.string]
    static let invariant: Bool = true
    static let mutating: Bool = true

    func evaluate(_ params: CallValues) -> LeafData { __MajorBug("Mutating method") }
    func mutatingEvaluate(_ params: CallValues) -> (mutate: LeafData?, result: LeafData) {
        let cache = params[0].string!
        var operand = cache
        let result = f(&operand)
        return (operand != cache ? operand.leafData : nil, .string(result))
    }
    
    private init(_ map: @escaping (inout String) -> String?) { f = map }
    private let f: (inout String) -> String?
    
    static let popLast: Self = .init({ $0.popLast().map{String($0)} })
}

/// (String, String) -> Bool
internal struct StrStrToBoolMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string]), .types([.string])]
    static let returns: Set<LeafDataType> = [.bool]
    static let invariant: Bool = true
    static let mutating: Bool = false

    func evaluate(_ params: CallValues) -> LeafData { .bool(f(params[0].string!, params[1].string!)) }
    
    private init(_ map: @escaping (String, String) -> Bool) { f = map }
    private let f: (String, String) -> Bool
    
    static let hasPrefix: Self = .init({ $0.hasPrefix($1) })
    static let hasSuffix: Self = .init({ $0.hasSuffix($1) })
}

/// (String) -> Int
internal struct StrToIntMap: LeafMethod {
    static let callSignature: CallParameters = [.types([.string])]
    static let returns: Set<LeafDataType> = [.int]
    static let invariant: Bool = true
    static let mutating: Bool = false
    
    init(_ map: @escaping (String) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LeafData { .int(f(params[0].string!)) }
    private let f: (String) -> Int
    
    static let count: Self = .init({ $0.count })
}

internal struct DictionaryCast: LeafFunction {
    static let callSignature: CallParameters = [.types([.dictionary])]
    static let returns: Set<LeafDataType> = [.dictionary]
    static let invariant: Bool = true
    static let mutating: Bool = false

    func evaluate(_ params: CallValues) -> LeafData { params[0].celf == .dictionary ? params[0] : .trueNil }
}


internal extension LeafMethod {
    func mutatingEvaluate(_ params: CallValues) -> (mutate: LeafData?, result: LeafData) {
        if !Self.mutating { __MajorBug("Mutating evaluation called on non-mutating method") }
        return (nil, .trueNil)
    }
}
