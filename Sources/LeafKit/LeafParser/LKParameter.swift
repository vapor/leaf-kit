/// A concrete parameter object that can be stored inside a LeafAST, either as an expression/function/block
/// parameter or as a passthrough atomic object at the top level of an AST
///
/// ```
/// // Atomic Invariants
/// case value(LeafData)            // Parameter.literal
/// case keyword(LeafKeyword)       // Parameter.keyword - unvalued
/// case `operator`(LeafOperator)   // Parameter.operator - limited subset
/// // Atomic Symbols
/// case variable(LKVariable)     // Parameter.variable
/// // Expression
/// case expression(LKExpression) // A constrained 2-3 value Expression
/// // Tuple
/// case tuple([LKParameter])     // A 0...n array of LeafParameters
/// // Function - Single exact match function
/// case function(String, LeafFunction, [LKParameter], LKParameter?)
/// // Dynamic - Multiple potential matching overloaded functions (filtered)
/// case dynamic(String, [(LeafFunction, LKTuple?)], [LKParameter], LKParameter?)
///
internal struct LKParameter: LKSymbol {
    // MARK: - Passthrough generators

    /// Generate a `LKParameter` holding concrete `LeafData`
    static func value(_ store: LKData) -> LKParameter { .init(.value(store)) }

    /// Generate a `LKParameter` holding a valid `.variable`
    static func variable(_ store: LKVariable) -> LKParameter { .init(.variable(store)) }

    /// Generate a `LKParameter` holding a validated `LKExpression`
    static func expression(_ store: LKExpression) -> LKParameter { .init(.expression(store)) }

    /// Generate a `LKParameter` holding an available `LeafOperator`
    static func `operator`(_ store: LeafOperator) -> LKParameter {
        if store.parseable { return .init(.operator(store)) }
        __MajorBug("Operator not available")
    }

    /// Generate a `LKParameter` hodling a validated `LeafFunction` and its concrete parameters
    static func function(_ name: String,
                         _ function: LeafFunction,
                         _ params: LKTuple?,
                         _ operand: LKVariable? = nil) -> LKParameter {
        .init(.function(name, function, params, operand)) }
    
    static func dynamic(_ name: String,
                        _ matches: [(LeafFunction, LKTuple?)],
                        _ params: LKTuple?,
                        _ operand: LKVariable? = nil) -> LKParameter {
        .init(.dynamic(name, matches, params, operand)) }

    // MARK: - Auto-reducing generators

    /// Generate a `LKParameter`, auto-reduce to a `.value` or .`.variable` or a non-evaluable`.keyword`
    static func keyword(_ store: LeafKeyword,
                        reduce: Bool = false) -> LKParameter {
        if !store.isEvaluable
                      || !reduce { return .init(.keyword(store)) }
        if store.isBooleanValued { return .init(.value(.bool(store.bool!))) }
        if store == .`self`      { return .init(.variable(.`self`)) }
        if store == .nil         { return .init(.value(.trueNil)) }
        __MajorBug("Unhandled evaluable keyword")
    }

    /// Generate a `LKParameter` holding a tuple of `LeafParameters` - auto-reduce multiple nested parens and decay to trueNil if void
    static func tuple(_ store: LKTuple) -> LKParameter {
        if store.count > 1 { return .init(.tuple(store)) }
        var store = store
        while case .tuple(let s) = store[0]?.container, s.count == 1 { store = s }
        return store.isEmpty ? .init(.value(.trueNil)) : store[0]!
    }

    /// `[` is always invalid in a parsed AST and is used as a magic value to avoid needing a nil LKParameter
    static let invalid: LKParameter = .init(.operator(.subOpen))

    // MARK: - Stored Properties
    
    /// Actual storage for the object
    private(set) var container: Container { didSet { setStates() } }

    // MARK: - LKSymbol
    
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>
    
    /// Will always resolve to a new LKParameter
    func resolve(_ symbols: LKVarStack) -> Self { isValued ? .init(container.resolve(symbols)) : self }
    /// Will always evaluate to a .value container, potentially holding trueNil
    func evaluate(_ symbols: LKVarStack) -> LKData { container.evaluate(symbols) }
    
    var description: String { container.description }
    var short: String { isTuple ? container.description : container.short }
    
    // MARK: - Internal Only
    
    var `operator`: LeafOperator? {
        guard case .operator(let o) = container else { return nil }
        return o
    }

    var data: LKData? {
        switch container {
            case .value(let d): return d
            case .keyword(let k) where k.isBooleanValued: return .bool(k.bool)
            default: return nil
        }
    }

    var baseType: LKDType? {
        switch container {
            case .expression(let e)     : return e.baseType
            case .value(let d)          : return d.celf
            case .keyword, .operator,
                 .tuple, .variable,
                 .dynamic               : return nil
            case .function(_, let f, _, _) :
                return type(of: f).returns.count == 1 ? type(of: f).returns.first : nil
        }
    }

    /// Whether the parameter can return actual `LeafData` when resolved
    var isValued: Bool {
        switch container {
            case .value, .variable,
                 .function, .dynamic : return true
            case .operator           : return false
            case .tuple(let t)       : return t.isEvaluable
            case .keyword(let k)     : return k.isEvaluable
            case .expression(let e)  : return e.form.exp != .custom            
        }
    }
    
    /// Rough estimate estimate of output size
    var underestimatedSize: UInt32 {
        switch container {
            case .expression, .value,
                 .variable, .function,
                 .dynamic          : return 16
            case .operator, .tuple : return 0
            case .keyword(let k)   : return k.isBooleanValued ? 4 : 0
        }
    }

    // MARK: - Private Only

    /// Unchecked initializer - do not use directly except through static factories that guard conditions
    private init(_ store: Container) {
        self.container = store
        self.symbols = .init()
        self.resolved = false
        self.invariant = false
        setStates()
    }

    /// Cache the stored states for `symbols, resolved, invariant`
    mutating private func setStates() {
        switch container {
            case .operator, .keyword:
                symbols = []
                resolved = true
                invariant = true
            case .value(let v):
                symbols = []
                resolved = true
                invariant = v.container.isLazy ? v.invariant : true
            case .variable(let v):
                symbols = [v]
                resolved = false
                invariant = true
            case .expression(let e):
                symbols = e.symbols
                resolved = false
                invariant = e.invariant
            case .tuple(let t):
                symbols = t.symbols
                resolved = t.resolved
                invariant = t.invariant
            case .function(_, let f, let p, _):
                resolved = p?.resolved ?? true
                symbols = p?.symbols ?? []
                invariant = f.invariant && p?.invariant ?? true
            case .dynamic(_, let f, let p, _):
                resolved = p?.resolved ?? true
                symbols = p?.symbols ?? []
                invariant = f.allSatisfy {$0.0.invariant} && p?.invariant ?? true
        }
    }

    private var isTuple: Bool { if case .tuple = container { return true } else { return false } }
    
    // MARK: - Internal Scoped Type
    
    /// Wrapped storage object for the actual value the `LKParameter` holds
    enum Container: LKSymbol {
        /// A concrete `LeafData`
        case value(LKData)
        /// A `LeafKeyword` (may previously have decayed if evaluable to a different state)
        case keyword(LeafKeyword)
        /// A `LeafOperator`
        case `operator`(LeafOperator)
        /// An `LKVariable` key
        case variable(LKVariable)
        /// A constrained 2-3 value `LKExpression`
        case expression(LKExpression)
        /// A 1...n array/dictionary of LeafParameters either all with or without labels
        case tuple(LKTuple)
        // FIXME: Need to store all potentially resolvable functions at parse time
        /// A `LeafFunction`(s) - tuple is 1...n and may have 0...n labels - nil when empty params
        case function(String, LeafFunction, LKTuple?, LKVariable?)
        /// A dynamic LeafFunction where multiple hits were found at Parse but can't disambiguate then
        case dynamic(String, [(LeafFunction, LKTuple?)], LKTuple?, LKVariable?)

        // MARK: LKSymbol
        
        var description: String {
            switch self {
                case .value(let v)              : return v.description
                case .keyword(let k)            : return "keyword(\(k.description))"
                case .operator(let o)           : return "operator(\(o.description)"
                case .variable(let v)           : return "variable(\(v.description))"
                case .expression(let e)         : return "expression(\(e.description))"
                case .tuple(let t) where t.collection
                                                : return "\(t.labels.isEmpty ? "array" : "dictionary")\(short)"
                case .tuple                     : return "tuple\(short)"
                case .dynamic(let f, _, let p, _),
                     .function(let f, _, let p, _) : return "\(f)\(p?.description ?? "()")"
            }
        }
        
        var short: String {
            switch self {
                case .value(let d)              : return d.short
                case .keyword(let k)            : return k.short
                case .operator(let o)           : return o.short
                case .variable(let s)           : return s.short
                case .expression(let e)         : return e.short
                case .tuple(let t)  where t.collection
                                                : return "\(t.labels.isEmpty ? t.short : t.description)"
                case .tuple(let t)              : return "\(t.short)"
                case .dynamic(let f, _, let p, _),
                     .function(let f, _, let p, _) : return "\(f)\(p?.short ?? "()")"
            }
        }

        var resolved: Bool {
            switch self {
                case .keyword, .operator    : return true
                case .variable              : return false
                case .expression(let e)     : return e.resolved
                case .value(let v)          : return v.resolved
                case .tuple(let t),
                     .function(_, _, .some(let t), _) : return t.resolved
                case .function              : return true
                case .dynamic               : return false
            }
        }
        
        var invariant: Bool {
            switch self {
                case .keyword, .operator,
                     .variable                  : return true
                case .expression(let e)         : return e.invariant
                case .tuple(let t)              : return t.invariant
                case .value(let v)              : return v.invariant
                case .function(_, let f, let p, _) : return f.invariant && p?.invariant ?? true
                case .dynamic(_, let f, let p, _)  : return f.allSatisfy({$0.0.invariant}) && p?.invariant ?? true
            }
        }
        
        var symbols: Set<LKVariable> {
            switch self {
                case .keyword, .operator, .value : return []
                case .variable(let v)            : return [v]
                case .expression(let e)          : return e.symbols
                case .tuple(let t),
                     .dynamic(_, _, .some(let t), _),
                     .function(_, _, .some(let t), _): return t.symbols
                case .function, .dynamic         : return []
            }
        }

        func resolve(_ symbols: LKVarStack) -> Self {
            if resolved && invariant { return .value(evaluate(symbols)) }
            switch self {
                case .value, .keyword,
                     .operator          : return self
                case .expression(let e) : return .expression(e.resolve(symbols))
                case .variable(let v)   : if let value = symbols.match(v)
                                               { return .value(value) }
                                          else { return self }
                case .tuple(let t)
                    where t.isEvaluable : return .tuple(t.resolve(symbols))
                case .function(let n, let f, .some(var p), let m)
                                        : p.values = p.values.map { $0.resolve(symbols) }
                                          return .function(n, f, p, m)
                case .dynamic(let n, _, .some(var p), let m)
                                        : p.values = p.values.map { $0.resolve(symbols) }
                                          let result = LKConf.entities.validateFunction(n, p)
                                          switch result {
                                              case .failure : return .value(.trueNil)
                                              case .success(let f) where f.count == 1: return .function(n, f[0].0, f[0].1, m)
                                              case .success(let f): return .dynamic(n, f, p, m) }
                case .function, .dynamic: return self
                case .tuple             : __MajorBug("Unevaluable Tuples should not exist")
            }
        }

        func evaluate(_ symbols: LKVarStack) -> LeafData {
            switch self {
                case .value(let v)              : return v.evaluate(symbols)
                case .variable(let v)           : return symbols.match(v) ?? .trueNil
                case .expression(let e)         : return e.evaluate(symbols)
                case .tuple(let t)
                        where t.isEvaluable     : return t.evaluate(symbols)
                case .function(_, let f as Evaluate, _, _)
                                                :
                    /// `Define` parameter was found - evaluate if non-value, and return
                    if let x = symbols.match(.define(f.identifier))?.container {
                        if case .evaluate(let x) = x { return x.evaluate(symbols) }
                        else { return x.evaluate } }
                    /// Or `Evaluate` had a default - evaluate and return that
                    else if let x = f.defaultValue { return x.evaluate(symbols) }
                    return .trueNil /// Otherwise, nil
                case .function(_, var f, let p, let v) :
                    guard let params = CallValues(f.sig, p, symbols),
                       params.values.first(where: { $0.celf == .void }) == nil
                    else { return .trueNil }
                    if var unsafeF = f as? LeafUnsafeEntity { unsafeF.userInfo = symbols[0].unsafe; f = unsafeF as! LeafFunction }
                    if let op = v, let f = f as? LeafMethod {
                        let x = f.mutatingEvaluate(params)
                        if let updated = x.0 { symbols.update(op, updated) }
                        return x.1
                    } else { return f.evaluate(params) }
                case .dynamic(_, let F, _, let v):
                    var x: LKTuple = .init()
                    var matches: [(LeafFunction, CallValues)] = []
                    for f in F {
                        x = f.1 ?? .init()
                        x.values = x.values.map { .value($0.evaluate(symbols)) }
                        if let params = CallValues(f.0.sig, f.1, symbols),
                           params.values.first(where: {$0.celf == .void}) == nil {
                            matches.append((f.0, params))
                        }
                    }
                    if matches.count != 1 { return .trueNil }
                    let f = matches[0].0
                    let params = matches[0].1
                    if let v = v, let f = f as? LeafMethod {
                        let x = f.mutatingEvaluate(params)
                        if let updated = x.0 { symbols.update(v, updated) }
                        return x.1
                    } else { return f.evaluate(params) }
                case .keyword(let k)
                        where k.isEvaluable     : let x = LKParameter.keyword(k, reduce: true)
                                                  return x.container.evaluate(symbols)
                case .keyword, .operator        : return .trueNil
                case .tuple                     : __MajorBug("Unevaluable Tuples should not exist")
            }
        }

    }
}
