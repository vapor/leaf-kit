// MARK: Subject to change prior to 1.0.0 release
// MARK: -

internal struct Leaf4Syntax: SymbolPrintable {
    internal enum Container {
        // Passthrough and raw are atomic syntaxes.
        case passthrough(LeafParameter.Container) // where LP.isValued
        case raw(RawBlock)
        
        
        case block(String, LeafBlock, LeafTuple?)
        // A scope - special case of nil for placeholders
        case scope(table: Int?) // Scopes
    }
    
    internal private(set) var container: Container
    
    static func raw(_ store: RawBlock) -> Leaf4Syntax {
        .init(container: .raw(store))
    }
    static func passthrough(_ store: LeafParameter) -> Leaf4Syntax {
        .init(container: .passthrough(store.container))
    }
    static func block(_ name: String,
                      _ block: LeafBlock,
                      _ params: LeafTuple?) -> Leaf4Syntax {
        .init(container: .block(name, block, params))
    }
    static func scope(_ table: Int?) -> Leaf4Syntax { .init(container: .scope(table: table)) }
    
    var description: String {
        switch container {
            case .block(let f, _, let t): return "\(f)\(t?.description ?? "()"):"
            case .passthrough(let p): return p.description
            case .raw(let r): return "raw(\(type(of: r)): \"\(r.contents.replacingOccurrences(of: "\n", with: "\\n"))\")"
            case .scope(let table) where table != nil: return "scope(table: \(table!))"
            case .scope: return "scope(undefined)"
        }
    }
    var short: String {
        switch container {
            case .block(let f, _, let t): return "\(f)\(t?.short ?? "()"):"
            case .passthrough(let p): return p.short
            case .raw(let r): return "raw(\(type(of: r)): \(r.byteCount.formatBytes)))"
            case .scope(let table) where table != nil: return "scope(table: \(table!))"
            case .scope: return "scope(undefined)"
        }
    }
}

extension Array where Element == [Leaf4Syntax] {
    var formatted: String { self[0].print(0, self) }
    var terse: String { self[0].print(0, self, true) }
}

extension Array where Element == Leaf4Syntax {
    func print(_ depth: Int = 0, _ tables: [[Leaf4Syntax]], _ terse: Bool = false) -> String {
        let rule = (!terse) ? String(repeating: " ", count: depth) + repeatElement("-", count: 60 - depth) + "\n" : ""
        var result = rule
        let maxBuffer = String(self.count - 1).count
        for index in self.indices {
            if case .raw(let b as ByteBuffer) = self[index].container,
               terse, b.contents == Character.newLine.description { continue }
            let prefix = String(repeating: " ", count: maxBuffer - String(index).count) + "\(index): "
            result += "\(indent(depth) + prefix + (terse ? self[index].short : self[index].description))\n"
            if case .scope(.some(let table)) = self[index].container {
                result += table.signum() == -1 ? "\(String(repeating: " ", count: maxBuffer + 2) + indent(depth + 1))No scope set"
                          : tables[table].print(depth + maxBuffer + 2, tables, terse)
            }
        }
        result += rule
        if depth == 0 { result.removeLast(1) }
        return result
    }
    static let indent = " "
    func indent(_ depth: Int = 0) -> String { .init(repeating: Self.indent, count: depth) }
}


/// A concrete parameter object that can be stored inside a LeafAST, either as an expression/function/block
/// parameter or as a passthrough atomic object at the top level of an AST
///
/// ```
/// // Atomic Invariants
/// case value(LeafData)            // Parameter.literal
/// case keyword(LeafKeyword)       // Parameter.keyword - unvalued
/// case `operator`(LeafOperator)   // Parameter.operator - limited subset
/// // Atomic Symbols
/// case variable(LeafVariable)     // Parameter.variable
/// // Expression
/// case expression(LeafExpression) // A constrained 2-3 value Expression
/// // Tuple
/// case tuple([LeafParameter])     // A 0...n array of LeafParameters
/// // Function
/// case function(String, LeafFunction, [LeafParameter])
///
internal struct LeafParameter: LeafSymbol {
/*
    /// The signature for what concrete values can match a particular parameter
    internal enum Signature: SymbolPrintable {
        case data(Set<LeafDataType>)
        case keyword(Set<LeafKeyword>)
        case `operator`(Set<LeafOperator>)
        
        /// `case(Members)`
        var description: String {
            switch self {
                case .data(let d)     : return "\(short)(\(d.description))"
                case .keyword(let k)  : return "\(short)(\(k.description))"
                case .operator(let o) : return "\(short)(\(o.description))"
            }
        }
        
        /// Signature case
        var short: String {
            switch self {
                case .data     : return "datatypes"
                case .keyword  : return "keywords"
                case .operator : return "operators"
            }
        }
    }*/
    
    // MARK: - Passthrough generators
    
    /// Generate a `LeafParameter` holding concrete `LeafData`
    static func value(_ store: LeafData) -> LeafParameter { .init(.value(store)) }
    
    /// Generate a `LeafParameter` holding a fully scoped `.variable`
    static func variable(_ store: LeafVariable) -> LeafParameter { .init(.variable(store)) }
    
    /// Generate a `LeafParameter` holding a validated `LeafExpression`
    static func expression(_ store: LeafExpression) -> LeafParameter { .init(.expression(store)) }
    
    /// Generate a `LeafParameter` holding an available `LeafOperator`
    static func `operator`(_ store: LeafOperator) -> LeafParameter {
        if store.parseable { return .init(.operator(store)) }
        __MajorBug("Operator not available")
    }
    
    /// Generate a `LeafParameter` hodling a validated `LeafFunction` and its concrete parameters
    static func function(_ name: String,
                         _ function: LeafFunction,
                         _ params: LeafTuple) -> LeafParameter {
        .init(.function(name, function, params)) }
    
    // MARK: - Auto-reducing generators
    
    /// Generate a `LeafParameter`, auto-reduce to a `.value` or .`.variable` or a non-evaluable`.keyword`
    static func keyword(_ store: LeafKeyword, reduce: Bool = false) -> LeafParameter {
        if !store.isEvaluable
                      || !reduce { return .init(.keyword(store)) }
        if store.isBooleanValued { return .init(.value(.bool(store.bool!))) }
        if store == .`self`      { return .init(.variable(.`self`)) }
        if store == .nil         { return .init(.value(.trueNil)) }
        __MajorBug("Unhandled evaluable keyword")
    }
    
    /// Generate a `LeafParameter` holding a tuple of `LeafParameters` - auto-reduce multiple nested parens and decay to trueNil if void
    static func tuple(_ store: LeafTuple) -> LeafParameter {
        if store.count > 1 { return .init(.tuple(store)) }
        var store = store
        while case .tuple(let s) = store[0]?.container, s.count == 1 { store = s }
        return store.isEmpty ? .init(.value(.trueNil)) : store[0]!
    }

    // `[` is always invalid in a parsed AST and is used as a magic value
    static let invalid: LeafParameter = .init(.operator(.subOpen))
    
    /// Wrapped storage object for the actual value the `LeafParameter` holds
    enum Container: LeafSymbol {
        // Atomic Invariants
        case value(LeafData)              // Parameter.literal
        case keyword(LeafKeyword)         // Parameter.keyword - unvalued
        case `operator`(LeafOperator)     // Parameter.operator - limited subset
        // Atomic Symbols
        case variable(LeafVariable)       // Parameter.variable
        // Expression
        case expression(LeafExpression)   // A constrained 2-3 value Expression
        // Tuple
        case tuple(LeafTuple)             // A 0...n array of LeafParameters
        // Function
        case function(String, LeafFunction, LeafTuple)
        
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
        var symbols: Set<LeafVariable> {
            switch self {
                case .keyword, .operator, .value : return []
                case .variable(let v)            : return [v]
                case .expression(let e)          : return e.symbols
                case .tuple(let t),
                     .function(_, _, let t)      : return t.symbols
            }
        }
        
        func resolve(_ symbols: SymbolMap) -> Self {
            if resolved && invariant { return .value(evaluate(symbols)) }
            switch self {
                case .value, .keyword, .operator: return self
                case .expression(let e): return .expression(e.resolve(symbols))
                case .variable(let v):
                    // DO NOT contextualize - resolve may be called during parse
                    // and not know of unscoped variables' existence yet
                    if let value = symbols[v] { return .value(value) }
                    return self
                case .function(let n, let f, var p):
                    p.values = p.values.map { $0.resolve(symbols) }
                    return .function(n, f, p)
                case .tuple: __MajorBug("Tuples should not exist")
            }
        }
        
        func evaluate(_ symbols: SymbolMap) -> LeafData {
            switch self {
                case .value(let v):               return v.evaluate()
                case .variable(let v):            return symbols.match(v)
                case .expression(let e):          return e.evaluate(symbols)
                case .function(_, let f, let p):
                    if let params = ParameterValues(f.sig, p, symbols) {
                        return f.evaluate(params) }
                    else { return .trueNil }
                case .keyword(let k) where k.isEvaluable:
                    let reduced = LeafParameter.keyword(k, reduce: true).container
                    return reduced.evaluate(symbols)
                case .keyword, .operator: return .trueNil
                case .tuple: __MajorBug("Tuples should not exist")
            }
        }

        
    }

    /// Actual storage for the object
    internal private(set) var container: Container { didSet { setStates() } }
    
    internal private(set) var resolved: Bool
    internal private(set) var invariant: Bool
    internal private(set) var symbols: Set<LeafVariable>

    internal var concreteType: LeafDataType? {
        switch container {
            case .expression(let e): return e.concreteType
            case .value(let d): return d.concreteType
            case .keyword, .operator, .tuple, .variable: return nil
            case .function(_, let f, _):
                return type(of: f).returns.count == 1 ? type(of: f).returns.first : nil
        }
    }
    
    /// Will always resolve to a new LeafParameter
    func resolve(_ symbols: SymbolMap) -> Self { .init(container.resolve(symbols)) }
    /// Will always evaluate to a .value container, potentially holding trueNil
    func evaluate(_ symbols: SymbolMap) -> LeafData { container.evaluate(symbols) }
    
    
    /// Whether the parameter can return actual `LeafData` when resolved
    internal var isValued: Bool {
        switch container {
            case .value, .variable  : return true
            case .operator, .tuple  : return false
            case .keyword(let k)    : return k.isEvaluable
            case .expression(let e) : return e.form.0 == .calculation
            case .function          : return true
        }
    }
    
    internal var description: String { container.description }
    internal var short: String { container.short }
    
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
    
    
    internal var `operator`: LeafOperator? {
        guard case .operator(let o) = container else { return nil }
        return o
    }
    
    internal var data: LeafData? {
        switch container {
            case .value(let d): return d
            case .keyword(let k) where k.isBooleanValued: return .bool(k.bool)
            default: return nil
        }
    }

}


internal struct LeafTuple: LeafSymbol {
    func resolve(_ symbols: SymbolMap) -> Self { self }
    func evaluate(_ symbols: SymbolMap) -> LeafData { .trueNil }
    
    subscript(index: String) -> LeafParameter? {
        get { self[labels[index] ?? -1] }
        set { if values.indices.contains(labels[index] ?? -1)
                { self[labels[index]!] = newValue } }
    }
    subscript(index: Int) -> LeafParameter? {
        get { values.indices.contains(index) ? values[index] : nil }
        set { if values.indices.contains(index) { values[index] = newValue! } }
    }
    
    var values: [LeafParameter] { didSet { setStates() } }
    var labels: [String: Int]
    
    init(_ tuple: [(label: String?, param: LeafParameter)] = []) {
        self.values = []
        self.labels = [:]
        self.symbols = []
        self.resolved = false
        self.invariant = false
        for index in tuple.indices {
            values.append(tuple[index].param)
            if let label = tuple[index].label { labels[label] = index }
        }
        setStates()
    }
    
    // MARK: - Fake Collection Adherence
    var isEmpty: Bool { values.isEmpty }
    var count: Int { values.count }
    var enumerated: [(label: String?, value: LeafParameter)] {
        let inverted = Dictionary(uniqueKeysWithValues: labels.map { ($0.value, $0.key) })
        return values.enumerated().map { (inverted[$0.offset], $0.element) }
    }
    
    // MARK: - SymbolContainer
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LeafVariable>
    
//    func resolve(_ symbols: SymbolMap? = nil) -> SymbolicBox {
//        let results = values.map { $0.resolve(symbols) }
//        var resolved: [LeafParameter] = []
//        for index in values.indices {
//            switch results[index] {
//                case (.none, .none): return (nil, nil)
//                case (_, .some(let d)): resolved.append(.value(d))
//                case (.some(let p), _): resolved.append(p)
//            }
//        }
//        return (.init(labels: labels, values: resolved), nil)
//    }
//
    private init(labels: [String: Int], values: [LeafParameter]) {
        self.labels = labels
        self.values = values
        self.resolved = values.allSatisfy { $0.resolved }
        self.invariant = values.allSatisfy { $0.invariant }
        self.symbols = values.reduce(into: .init()) { $0.formUnion($1.symbols) }
    }
    
    mutating private func setStates() {
        resolved = values.allSatisfy { $0.resolved }
        invariant = values.allSatisfy { $0.invariant }
        symbols = values.reduce(into: .init()) { $0.formUnion($1.symbols) }
    }
    
    mutating internal func append(_ more: Self) {
        self.values.append(contentsOf: more.values)
        more.labels.mapValues { $0 + self.count }.forEach { labels[$0.key] = $0.value }
    }
    
    // MARK: - SymbolPrintable
    
    /// `(_: value(1), isValid: bool(true), ...)`
    var description: String {
        let inverted = labels.map { ($0.value, $0.key) }
        var labeled: [String] = []
        for (index, value) in values.enumerated() {
            let label = inverted.first?.0 == index ? inverted.first!.1 : "_"
            labeled.append("\(label): \(value.description)")
        }
        return "(\(labeled.joined(separator: ", ")))"
    }
    /// `(value(1), bool(true), ...)`
    var short: String {
        "(\(values.map { $0.short }.joined(separator: ", ")))"
    }
}
