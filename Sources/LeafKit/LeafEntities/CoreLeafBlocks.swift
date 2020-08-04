// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Control Flow: Looping

/// `#for(value in collection):` or `#for((index, value) in collection):`
internal struct ForLoop: LeafBlock {
    static let parseSignatures: [String: [ParseParameter]]? = [
        /// `#for(_ in collection)`
        "discard": [.expression([.keyword([._]),
                                 .keyword([.in]),
                                 .callParameter])],
        /// `#for(value in collection)` where `index, key` set variable to collection index
        "single": [.expression([.unscopedVariable,
                               .keyword([.in]),
                               .callParameter])],
        /// `#for((index, value) in collection)`
        "tuple": [.expression([.tuple([.unscopedVariable, .unscopedVariable]),
                               .keyword([.in]),
                               .callParameter])]
    ]
    static let callSignature: [CallParameter] = [.types([.array, .dictionary, .string, .int])]
    
    static let invariant = true
    static let evaluable = false
    
    private(set) var scopeVariables: [String]? = nil
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> ForLoop {
        switch signature {
            case "tuple"   : return ForLoop(key: params[0], value: params[1])
            case "discard" : return ForLoop()
            case "single"  : return ["index", "key"].contains(params[0])
                                        ? ForLoop(key: params[0])
                                        : ForLoop(value: params[0])
            default        : __MajorBug("ForLoop called with no signature")
        }
    }
    
    internal init(key: String? = nil, value: String? = nil) {
        self.set = key != nil || value != nil
        self.setKey = key != nil ? true : false
        self.setValue = value != nil ? true : false
        if set {
            self.first = "isFirst"
            self.last = "isLast"
            self.scopeVariables = [first, last]
        }
        if setKey {
            self.key = key!
            self.scopeVariables?.append(self.key)
        }
        if setValue {
            self.value = value!
            self.scopeVariables?.append(self.value)
        }
    }
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount {
        if set {
            switch params[0].container {
                case .array(let a)      : cache = a.enumerated().map { (o, e) in
                    (setKey ? .int(o) : .trueNil, setValue ? e : .trueNil) }
                case .dictionary(let d) : cache = d.map { (k, v) in
                    (setKey ? .string(k) : .trueNil, setValue ? v : .trueNil) }
                case .int(let i)        : passes = i > 0 ? i : 0
                    for i in 0..<passes { cache.append(
                    (setKey ? .int(i) : .trueNil, setValue ? .int(i + 1) : .trueNil) )}
                case .string(let s)     : cache = Array(s).enumerated().map { (o, c) in
                    (setKey ? .int(o) : .trueNil, setValue ? .string(String(c)) : .trueNil) }
                default: __MajorBug("Non-container provided as parameter")
            }
            if cache.isEmpty { return .discard }
            passes = cache.count
            variables[first] = .bool(true)
            variables[last] = .bool(false)
        } else {
            switch params[0].container {
                case .array(let a)      : passes = a.count
                case .dictionary(let d) : passes = d.values.count
                case .int(let i)        : passes = i > 0 ? i : 0
                case .string(let s)     : passes = s.count
                default: __MajorBug("Non-container provided as parameter")
            }
            if cache.isEmpty { return .discard }
        }
        return reEvaluateScope(&variables)
    }
    
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount {
        guard pass < passes else { return .discard }
        guard set else { pass += 1; return .repeating(passes - pass + 1) }
        if pass == 1 { variables[first] = .bool(false) }
        if pass == passes - 1 { variables[last] = .bool(true) }
        if setKey   { variables[key] = cache[pass].0 }
        if setValue { variables[value] = cache[pass].1 }
        pass += 1
        return .repeating(passes - pass + 1)
    }
    
    var first: String = "#first"
    var last: String = "#last"
    var key: String = "#key"
    var value: String = "#value"
    var set: Bool
    var setKey: Bool
    var setValue: Bool
    
    var pass: Int = 0
    var passes: Int = 0
    var cache: [(LeafData, LeafData)] = []
}

/// `#while(bool):` - 0...n while
internal struct WhileLoop: LeafBlock {
    static let parseSignatures: [String : [ParseParameter]]? = nil
    static let callSignature: [CallParameter] = [.types([.bool])]
    
    static let invariant: Bool = true
    static let evaluable: Bool = false
    
    let scopeVariables: [String]? = nil
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> WhileLoop {.init()}
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount {
        params[0].bool! ? .once : .discard
    }
    
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount { __MajorBug("While loops never return non-nil") }
}

/// `#repeat(while: bool):` 1...n+1 while
internal struct RepeatLoop: LeafBlock {
    static let parseSignatures: [String : [ParseParameter]]? = nil
    static let callSignature: [CallParameter] = [.init(label: "while", types: [.bool])]
    
    static let invariant: Bool = true
    static let evaluable: Bool = false
    
    let scopeVariables: [String]? = nil
    
    var cache: Bool? = nil
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> RepeatLoop {.init()}
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount {
        let result: ScopeCount = cache != false ? .indefinite : .discard
        cache = params[0].bool!
        return result
    }
    
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount { __MajorBug("Repeat loops never return non-nil") }
}

// MARK: - Control Flow: Branching

/// `#if(bool)` - accepts `elseif, else`
struct IfBlock: ChainedBlock {
    static let chainsTo: [ChainedBlock.Type] = []
    static let chainAccepts: [ChainedBlock.Type] = [ElseIfBlock.self, ElseBlock.self]
    
    static let parseSignatures: [String : [ParseParameter]]? = nil
    static let callSignature: [CallParameter] = [.types([.bool])]
    
    static let invariant: Bool = true
    static let evaluable: Bool = true
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> IfBlock {.init()}
    
    let scopeVariables: [String]? = nil
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount {
        params[0].bool! ? .once : .discard
    }
        
    /// `#if(bool, valuedParameter #when true#, valuedParameter? = nil #when false#)`
    struct IfFunction: LeafFunction {
        static let callSignature: [CallParameter] = [
            .types([.bool]), .types(.any), .init(types: .any, optional: true, defaultValue: false)
        ]
        static let returns: Set<LeafDataType> = .any
        static let invariant: Bool = true        
        
        func evaluate(_ params: ParameterValues) -> LeafData {
            params[0].bool! ? params[1] : params[2]
        }
    }
}

/// `#elseif(bool)` - chains to `if, elseif`, accepts `elseif, else`
struct ElseIfBlock: ChainedBlock {
    static var chainsTo: [ChainedBlock.Type] = [ElseIfBlock.self, IfBlock.self]
    static var chainAccepts: [ChainedBlock.Type] = [ElseIfBlock.self, ElseBlock.self]
    
    static var parseSignatures: [String : [ParseParameter]]? = nil
    static var evaluable: Bool = false
    static var callSignature: [CallParameter] = [.types([.bool])]
    static var invariant: Bool = true
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> ElseIfBlock {.init()}
    
    let scopeVariables: [String]? = nil
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount {
        params[0].bool! ? .once : .discard
    }
}

/// `#elseif(bool)` - chains to `if, elseif` - end of chain
struct ElseBlock: ChainedBlock {
    static var chainsTo: [ChainedBlock.Type] = [ElseIfBlock.self, IfBlock.self]
    static var chainAccepts: [ChainedBlock.Type] = []
    
    static var parseSignatures: [String : [ParseParameter]]? = nil
    static var evaluable: Bool = false
    static var callSignature: [CallParameter] = []
    static var invariant: Bool = true
    
    static func instantiate(_ signature: String?, _ params: [String]) throws -> ElseBlock {.init()}
    
    let scopeVariables: [String]? = nil
    
    mutating func evaluateNilScope(_ params: ParameterValues, _ variables: inout [String: LeafData]) -> ScopeCount { .once }
}
