internal extension LeafEntities {
    func registerMutatingMethods() {
        use(MutatingStrStrMap.append      , asMethod: "append")
        use(MutatingStrToStrMap.popLast   , asMethod: "popLast")
        use(MutatingArrayAnyMap.append      , asMethod: "append")
        use(MutatingArrayToAnyMap.popLast , asMethod: "popLast")
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

/// Mutating (String) -> String
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

/// Mutating (Array) -> Any
internal struct MutatingArrayToAnyMap: LeafMutatingMethod, ArrayParam, AnyReturn {
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
        let cache = params[0].array!
        var operand = cache
        let result = f(&operand)
        return (operand != cache ? .array(operand) : nil,
                result != nil ? result! : .trueNil)
    }
    
    static let popLast: Self = .init({$0.popLast()})
    
    private init(_ map: @escaping (inout [LeafData]) -> LeafData?) { f = map }
    private let f: (inout [LeafData]) -> LeafData?
}

/// Mutating (Array, Any)
internal struct MutatingArrayAnyMap: LeafMutatingMethod, VoidReturn {
    static var callSignature: [LeafCallParameter] { [.array, .any] }
    
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LKData?, result: LKData) {
        let cache = params[0].array!
        var operand = cache
        f(&operand, params[1])
        return (operand != cache ? .array(operand) : nil, .trueNil)
    }
    
    static let append: Self = .init({$0.append($1)})
    
    private init(_ map: @escaping (inout [LeafData], LeafData) -> ()) { f = map }
    private let f: (inout [LeafData], LeafData) -> ()
}
