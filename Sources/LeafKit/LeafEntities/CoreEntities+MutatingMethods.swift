internal extension LeafEntities {
    func registerMutatingMethods() {
        use(MutatingStrStrMap.append     , asMethod: "append")
        use(MutatingStrToStrMap.popLast  , asMethod: "popLast")
    }
}
/// Mutating (String, String)
internal struct MutatingStrStrMap: LeafMutatingMethod, VoidReturn {
    static let callSignature:[LeafCallParameter] = [.string, .string]

    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
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
internal struct MutatingStrToStrMap: LeafMutatingMethod, StringReturn {
    static let callSignature:[LeafCallParameter] = [.string]

    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
        let cache = params[0].string!
        var operand = cache
        let result = f(&operand)
        return (operand != cache ? operand.leafData : nil, .string(result))
    }
    
    private init(_ map: @escaping (inout String) -> String?) { f = map }
    private let f: (inout String) -> String?
    
    static let popLast: Self = .init({ $0.popLast().map{String($0)} })
}
