internal extension LeafEntities {
    func registerIntReturns() {
        use(CollectionToIntMap.count , asMethod: "count")
        use(StrToIntMap.count        , asMethod: "count")
        use(IntIntToIntMap._min      , asFunction: "min")
        use(IntIntToIntMap._max      , asFunction: "max")
    }
}

/// (String) -> Int
internal struct StrToIntMap: LKMapMethod, StringParam, IntReturn {
    func evaluate(_ params: LeafCallValues) -> LKData { .int(f(params[0].string!)) }

    static let count: Self = .init({ $0.count })
    
    private init(_ map: @escaping (String) -> Int) { f = map }
    private let f: (String) -> Int
}

/// (Array || Dictionary.values) -> Int
internal struct CollectionToIntMap: LKMapMethod, CollectionsParam, IntReturn {
    func evaluate(_ params: LeafCallValues) -> LKData {
        switch params[0].container {
            case .dictionary(let x) : return .int(f(.init(x.values)))
            case .array(let x)      : return .int(f(.init(x)))
            default                 : return .error(internal: "Non-collection parameter") }
    }

    static let count: Self = .init({ $0.count })
    
    private init(_ map: @escaping (AnyCollection<LKData>) -> Int) { f = map }
    private let f: (AnyCollection<LKData>) -> Int
}

internal struct IntIntToIntMap: LKMapMethod, IntReturn {
    static var callSignature: [LeafCallParameter] = [.int, .int]
    
    func evaluate(_ params: LeafCallValues) -> LKData { .int(f(params[0].int!, params[1].int!)) }
    
    static let _min: Self = .init({ min($0, $1) })
    static let _max: Self = .init({ max($0, $1) })
    
    private init(_ map: @escaping (Int, Int) -> Int) { f = map }
    private let f: (Int, Int) -> Int
}
