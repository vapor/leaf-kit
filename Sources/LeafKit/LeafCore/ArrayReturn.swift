internal extension LeafEntities {
    func registerArrayReturns() {
        use(ArrayToArrayMap.indices     , asMethod: "indices")
        use(DictionaryToArrayMap.keys   , asMethod: "keys")
        use(DictionaryToArrayMap.values , asMethod: "values")
    }
}

internal struct ArrayToArrayMap: LKMapMethod, ArrayParam, ArrayReturn {
    func evaluate(_ params: LeafCallValues) -> LKData { .array(f(params[0].array!)) }

    static let indices: Self = .init({$0.indices.map {$0.leafData}})
    
    private init(_ map: @escaping ([LKData]) -> [LKData]) { f = map }
    private let f: ([LKData]) -> [LKData]
}

internal struct DictionaryToArrayMap: LKMapMethod, DictionaryParam, ArrayReturn {
    func evaluate(_ params: LeafCallValues) -> LKData { .array(f(params[0].dictionary!)) }

    static let keys: Self = .init({Array($0.keys.map {$0.leafData})})
    static let values: Self = .init({Array($0.values)})
    
    private init(_ map: @escaping ([String: LKData]) -> [LKData]) { f = map }
    private let f: ([String: LKData]) -> [LKData]
}
