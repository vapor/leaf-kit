internal extension LeafEntities {
    func registerIntReturns() {
        use(CollectionToIntMap.count , asMethod: "count")
        use(StrToIntMap.count        , asMethod: "count")
    }
}

/// (String) -> Int
internal struct StrToIntMap: LKMapMethod, IntReturn {
    static let callSignature: CallParameters = [.string]
    
    init(_ map: @escaping (String) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LKData { .int(f(params[0].string!)) }
    private let f: (String) -> Int
    
    static let count: Self = .init({ $0.count })
}

/// (Array || Dictionary.values) -> Int
internal struct CollectionToIntMap: LKMapMethod, IntReturn {
    static let callSignature: CallParameters = [.collections]

    init(_ map: @escaping (AnyCollection<LKData>) -> Int) { f = map }

    func evaluate(_ params: CallValues) -> LKData {
        switch params[0].container {
            case .dictionary(let x) : return .int(f(.init(x.values)))
            case .array(let x)      : return .int(f(.init(x)))
            default                 : return .trueNil }
    }
    
    private let f: (AnyCollection<LKData>) -> Int
    
    static let count: Self = .init({ $0.count })
}
