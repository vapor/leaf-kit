internal extension LeafEntities {
    func registerBoolReturns() {
        use(StrStrToBoolMap.hasPrefix , asMethod: "hasPrefix")
        use(StrStrToBoolMap.hasSuffix , asMethod: "hasSuffix")
        
        use(CollectionToBoolMap.isEmpty , asMethod: "isEmpty")
        use(StrToBoolMap.isEmpty        , asMethod: "isEmpty")
        
        use(CollectionElementToBoolMap.contains , asMethod: "contains")
        use(StrStrToBoolMap.contains            , asMethod: "contains")
    }
}

/// (Array || Dictionary.values) -> Bool
internal struct CollectionToBoolMap: LKMapMethod, BoolReturn {
    static let callSignature: CallParameters = [.collections]

    init(_ map: @escaping (AnyCollection<LKData>) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LKData {
        switch params[0].container {
            case .dictionary(let x) : return .bool(f(.init(x.values)))
            case .array(let x)      : return .bool(f(.init(x)))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LKData>) -> Bool
    
    static let isEmpty: Self = .init({ $0.isEmpty })
}

/// (Array | Dictionary, Any) -> Bool
internal struct CollectionElementToBoolMap: LKMapMethod, BoolReturn {
    static let callSignature: CallParameters = [.collections, .any]

    init(_ map: @escaping (AnyCollection<LKData>, LKData) -> Bool) { f = map }

    func evaluate(_ params: CallValues) -> LKData {
        switch params[0].container {
            case .dictionary(let x) : return .bool(f(.init(x.values), params[1]))
            case .array(let x)      : return .bool(f(.init(x), params[1]))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LKData>, LKData) -> Bool
    
    static let contains: Self = .init({for x in $0 where x.celf == $1.celf {if x == $1 { return true }}; return false})
}

/// (String, String) -> Bool
internal struct StrStrToBoolMap: LKMapMethod, BoolReturn {
    static let callSignature: CallParameters = [.string, .string]

    func evaluate(_ params: CallValues) -> LKData { .bool(f(params[0].string!, params[1].string!)) }
    
    private init(_ map: @escaping (String, String) -> Bool) { f = map }
    private let f: (String, String) -> Bool
    
    static let hasPrefix: Self = .init({ $0.hasPrefix($1) })
    static let hasSuffix: Self = .init({ $0.hasSuffix($1) })
    static let contains: Self = .init({ $0.contains($1) })
}

/// (String) -> Bool
internal struct StrToBoolMap: LKMapMethod, BoolReturn {
    static let callSignature: CallParameters = [.string]

    func evaluate(_ params: CallValues) -> LKData { .bool(f(params[0].string!)) }
    
    private init(_ map: @escaping (String) -> Bool) { f = map }
    private let f: (String) -> Bool
    
    static let isEmpty: Self = .init({ $0.isEmpty })
}
