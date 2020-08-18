// MARK: Subject to change prior to 1.0.0 release
// MARK: -

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
/// // Function
/// case function(String, LeafFunction, [LKParameter])
///
internal struct LKParameter: LKSymbol {
    // MARK: - Passthrough generators

    /// Generate a `LKParameter` holding concrete `LeafData`
    static func value(_ store: LeafData) -> LKParameter { .init(.value(store)) }

    /// Generate a `LKParameter` holding a fully scoped `.variable`
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
                         _ params: LKTuple) -> LKParameter {
        .init(.function(name, function, params)) }

    // MARK: - Auto-reducing generators

    /// Generate a `LKParameter`, auto-reduce to a `.value` or .`.variable` or a non-evaluable`.keyword`
    static func keyword(_ store: LeafKeyword, reduce: Bool = false) -> LKParameter {
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

    // `[` is always invalid in a parsed AST and is used as a magic value
    static let invalid: LKParameter = .init(.operator(.subOpen))

    /// Wrapped storage object for the actual value the `LKParameter` holds
    enum Container: LKSymbol {
        // Atomic Invariants
        case value(LeafData)              // Parameter.literal
        case keyword(LeafKeyword)         // Parameter.keyword - unvalued
        case `operator`(LeafOperator)     // Parameter.operator - limited subset
        // Atomic Symbols
        case variable(LKVariable)       // Parameter.variable
        // Expression
        case expression(LKExpression)   // A constrained 2-3 value Expression
        // Tuple
        case tuple(LKTuple)             // A 0...n array of LeafParameters, possibly with labels
        // Function(s)
        // FIXME: Need to store all potentially resolvable functions at parse time
        case function(String, LeafFunction, LKTuple)

        var description: String {
            switch self {
                case .value(let v)              : return v.description
                case .keyword(let k)            : return "keyword(\(k.description))"
                case .operator(let o)           : return "operator(\(o.description)"
                case .variable(let v)           : return "variable(\(v.description))"
                case .expression(let e)         : return "expression(\(e.description))"
                case .tuple(let t)              : return "tuple\(t.description)"
                case .function(let f, _, let p) : return "\(f)\(p.description)"
            }
        }
        var short: String {
            switch self {
                case .value(let d)              : return d.short
                case .keyword(let k)            : return k.short
                case .operator(let o)           : return o.short
                case .variable(let s)           : return s.short
                case .expression(let e)         : return e.short
                case .tuple(let t)              : return t.short
                case .function(let f, _, let p) : return "\(f)\(p.short)"
            }
        }

        var resolved: Bool {
            switch self {
                case .keyword, .operator    : return true
                case .variable              : return false
                case .expression(let e)     : return e.resolved
                case .value(let v)          : return v.resolved
                case .tuple(let t),
                     .function(_, _, let t) : return t.resolved
            }
        }
        var invariant: Bool {
            switch self {
                case .keyword, .operator,
                     .variable                  : return true
                case .expression(let e)         : return e.invariant
                case .tuple(let t)              : return t.invariant
                case .value(let v)              : return v.invariant
                case .function(_, let f, let p) : return f.invariant && p.invariant
            }
        }
        var symbols: Set<LKVariable> {
            switch self {
                case .keyword, .operator, .value : return []
                case .variable(let v)            : return [v]
                case .expression(let e)          : return e.symbols
                case .tuple(let t),
                     .function(_, _, let t)      : return t.symbols
            }
        }

        func resolve(_ symbols: LKVarTablePointer) -> Self {
            if resolved && invariant { return .value(evaluate(symbols)) }
            switch self {
                case .value, .keyword, .operator: return self
                case .expression(let e): return .expression(e.resolve(symbols))
                case .variable(let v):
                    // DO NOT contextualize - resolve may be called during parse
                    // and not know of unscoped variables' existence yet
                    if let value = symbols.pointee[v] { return .value(value) }
                    return self
                case .function(let n, let f, var p):
                    p.values = p.values.map { $0.resolve(symbols) }
                    return .function(n, f, p)
                case .tuple(let t) where t.isEvaluable:
                    return .tuple(t.resolve(symbols))
                case .tuple: __MajorBug("Unevaluable Tuples should not exist")
            }
        }

        func evaluate(_ symbols: LKVarTablePointer) -> LeafData {
            switch self {
                case .value(let v)              : return v.evaluate(symbols)
                case .variable(let v)           : return symbols.pointee.match(v) ?? .trueNil
                case .expression(let e)         : return e.evaluate(symbols)
                case .tuple(let t) where t.isEvaluable
                                                : return t.evaluate(symbols)
                case .function(_, let f, let p) :
                    // FIXME: This won't regress to overloaded functions
                    // Without an explicit cast, a parameter that was "any" type
                    // will have caught the first function of the name.
                    if let params = CallValues(f.sig, p, symbols),
                       params.values.first(where: { $0.celf == .void }) == nil
                    { return f.evaluate(params) } else { return .trueNil }
                case .keyword(let k)
                        where k.isEvaluable     : let x = LKParameter.keyword(k, reduce: true).container
                                                  return x.evaluate(symbols)
                case .keyword, .operator        : return .trueNil
                case .tuple                     : __MajorBug("Unevaluable Tuples should not exist")
            }
        }

    }

    /// Actual storage for the object
    private(set) var container: Container { didSet { setStates() } }

    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>

    var baseType: LeafDataType? {
        switch container {
            case .expression(let e): return e.baseType
            case .value(let d): return d.celf
            case .keyword, .operator, .tuple, .variable: return nil
            case .function(_, let f, _):
                return type(of: f).returns.count == 1 ? type(of: f).returns.first : nil
        }
    }

    /// Will always resolve to a new LKParameter
    func resolve(_ symbols: LKVarTablePointer) -> Self { .init(container.resolve(symbols)) }
    /// Will always evaluate to a .value container, potentially holding trueNil
    func evaluate(_ symbols: LKVarTablePointer) -> LKData { container.evaluate(symbols) }

    /// Whether the parameter can return actual `LeafData` when resolved
    var isValued: Bool {
        switch container {
            case .value, .variable  : return true
            case .operator          : return false
            case .tuple(let t)      : return t.isEvaluable
            case .keyword(let k)    : return k.isEvaluable
            case .expression(let e) : return e.form.exp != .custom
            case .function          : return true
        }
    }

    var description: String { container.description }
    var short: String { container.short }

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
            case .function(_, let f, let p):
                resolved = p.resolved
                symbols = p.symbols
                invariant = f.invariant && p.invariant
                // FIXME: Evaluate if resolved & invariant are true
        }
    }

    var `operator`: LeafOperator? {
        guard case .operator(let o) = container else { return nil }
        return o
    }

    var data: LeafData? {
        switch container {
            case .value(let d): return d
            case .keyword(let k) where k.isBooleanValued: return .bool(k.bool)
            default: return nil
        }
    }
}
