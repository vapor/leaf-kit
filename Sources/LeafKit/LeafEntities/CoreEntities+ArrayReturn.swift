internal extension LeafEntities {
    func registerArrayReturns() {
        use(ArrayToArrayMap.indices     , asMethod: "indices")
        use(DictionaryToArrayMap.keys   , asMethod: "keys")
        use(DictionaryToArrayMap.values , asMethod: "values")
    }
}


internal struct ArrayToArrayMap: LKMapMethod, ArrayReturn {
    static let callSignature: CallParameters = [.array]
    
    init(_ map: @escaping ([LKData]) -> [LKData]) { f = map }
    
    func evaluate(_ params: CallValues) -> LKData { .array(f(params[0].array!)) }
    
    private let f: ([LKData]) -> [LKData]
    
    static let indices: Self = .init({$0.indices.map {$0.leafData}})
}

internal struct DictionaryToArrayMap: LKMapMethod, ArrayReturn {
    static let callSignature: CallParameters = [.dictionary]
    
    init(_ map: @escaping ([String: LKData]) -> [LKData]) { f = map }
    
    func evaluate(_ params: CallValues) -> LKData { .array(f(params[0].dictionary!)) }
    
    private let f: ([String: LKData]) -> [LKData]
    
    static let keys: Self = .init({Array($0.keys.map {$0.leafData})})
    static let values: Self = .init({Array($0.values)})
}
