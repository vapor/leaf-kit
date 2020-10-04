internal extension LeafEntities {
    func registerMutatingMethods() {
        use(MutatingStrStrMap.append     , asMethod: "append")
        use(MutatingStrToStrMap.popLast  , asMethod: "popLast")
    }
}
/// Mutating (String, String)
internal struct MutatingStrStrMap: LeafMutatingMethod, StringStringParam, VoidReturn {
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
        let cache = params[0].string!
        var operand = cache
        f(&operand, params[1].string!)
        return (operand != cache ? operand.leafData : nil, .trueNil)
    }
    
    static let append: Self = .init({$0.append($1)})
    
    private init(_ map: @escaping (inout String, String) -> ()) { f = map }
    private let f: (inout String, String) -> ()
}


/// Mutating (String, Int) -> String
internal struct MutatingStrToStrMap: LeafMutatingMethod, StringParam, StringReturn {
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
        let cache = params[0].string!
        var operand = cache
        let result = f(&operand)
        return (operand != cache ? operand.leafData : nil, .string(result))
    }
    
    static let popLast: Self = .init({ $0.popLast().map{String($0)} })
    
    private init(_ map: @escaping (inout String) -> String?) { f = map }
    private let f: (inout String) -> String?
}
