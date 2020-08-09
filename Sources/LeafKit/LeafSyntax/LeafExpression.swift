// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

internal struct LeafExpression: LKSymbol {
    // MARK: - Internal Only
    // MARK: - Generators
        
    /// Generate a LeafExpression from a 2-3 value parameters that is internally resolvable
    static func express(_ params: [LeafParameter]) -> LeafExpression? {
        LeafExpression(params)
    }
    /// Generate a custom LeafExpression from any 2-3 value parameters, regardless of grammar
    static func expressAny(_ params: [LeafParameter]) -> LeafExpression? {
        LeafExpression(params, custom: true)
    }
    
    // MARK: - LeafSymbol Conformance
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>
    
    private(set) var concreteType: LeafDataType?
    
    internal func resolve(_ symbols: SymbolMap = [:]) -> Self {
        .init(.init(storage.map { $0.resolve(symbols) }), form)
    }
    
    internal func evaluate(_ symbols: SymbolMap = [:]) -> LeafData {
        if [.custom, .assignment].contains(form.0) { return .trueNil }
        let lhsData = lhs?.evaluate(symbols) ?? .trueNil
        let rhsData = rhs?.evaluate(symbols) ?? .trueNil
        switch form.1 {
            case .infix        : return evalInfix(lhsData, op!, rhsData)
            case .unaryPrefix  : return evalPrefix(op!, rhsData)
            case .unaryPostfix : return evalPostfix(lhsData, op!)
            case .none         : return .trueNil
        }
    }
    
    /// Short String description: `lhs op rhs` for assignment/calc, `first second third?` for custom
    internal var short: String {
        if form.0 == .custom {
            return "[\(storage.compactMap { $0.operator != .subOpen ? $0.short : nil }.joined(separator: " "))]"
        } else {
            return "[\([lhs?.short ?? "", op?.short ?? "", rhs?.short ?? ""].joined(separator: " "))]"
        }
    }
    /// String description: `expressionform[expression.short]`
    internal var description: String { "\(form.0.short)[\(short)]" }

    // MARK: - LeafExpression Specific
    /// The form expressions may take: `[.assignment, .calculation, .custom]`
    internal enum Form: String, LKPrintable {
        case assignment
        case calculation
        case custom
        
        internal var description: String  { rawValue }
        internal var short: String        { rawValue }
    }
    /// Tuple stating an object's particular expression form, and if relevant, operator form (not present for custom)
    internal typealias ContainerForm = (LeafExpression.Form, LeafOperator.Form?)
    
    /// Reveal the form of the expression, and of the operator when expression form is not .custom
    internal let form: ContainerForm
    
    /// Convenience referent name available when form is not .custom
    internal var op: LeafOperator?  {
        switch form.1 {
            case .infix,
                 .unaryPostfix : return storage[1].operator
            case .unaryPrefix  : return storage[0].operator
            case .none         : return nil
        }
    }
    /// Convenience referent name available when form is not .custom
    internal var lhs: LeafParameter? {
        switch form.1 {
            case .infix,
                 .unaryPostfix : return storage[0]
            case .unaryPrefix,
                 .none         : return nil
        }
    }
    /// Convenience referent name available when form is not .custom
    internal var rhs: LeafParameter? {
        switch form.1 {
            case .unaryPrefix  : return storage[1]
            case .infix        : return storage[2]
            case .unaryPostfix,
                 .none         : return nil
        }
    }
    /// Convenience referent name by position within expression
    internal var first: LeafParameter   { storage[0] }
    /// Convenience referent name by position within expression
    internal var second: LeafParameter  { storage[1] }
    /// Convenience referent name by position within expression
    internal var third: LeafParameter?   { storage[2].operator != .subOpen ? storage[2] : nil }
    
    // MARK: - Private Only
    /// Actual storage of 2 or 3 Parameters
    private var storage: ContiguousArray<LeafParameter> { didSet { setStates() } }
    
    /// Generate a `LeafExpression` if possible. Guards for expressibility unless "custom" is true
    private init?(_ params: [LeafParameter], custom: Bool = false) {
        // .assignment/.calculation is failable, .custom does not check
        guard (2...3).contains(params.count) else { return nil }
        
        var storage = params
        var form: ContainerForm
        
        if storage.count == 2 { storage.append(.invalid) }
        if custom { form = (.custom, nil) } else {
            guard let f = Self.expressible(params) else { return nil }
            form = f
        }
        // Rewrite prefix minus special case into rhs * -1
        if let unary = form.1, unary == .unaryPrefix,
           let op = params[0].operator, op == .minus {
            storage = [params[1], .operator(.multiply), .value(.int(-1))]
            form = (.calculation, .infix)
        }
        self = .init(.init(arrayLiteral: storage[0], storage[1], storage[2]), form)
    }
    
    private init(_ storage: ContiguousArray<LeafParameter>, _ form: ContainerForm) {
        self.storage = storage
        self.form = form
        self.resolved = false
        self.invariant = false
        self.symbols = []
        switch (lhs, rhs) {
            case (.some, .some):
                if lhs!.concreteType == rhs!.concreteType
                                { self.concreteType = lhs!.concreteType }
                else            { self.concreteType = nil }
            case (.some, .none) : self.concreteType = lhs!.concreteType
            case (.none, .some) : self.concreteType = rhs!.concreteType
            default             : self.concreteType = nil
        }
        setStates()
    }
    
    private mutating func setStates() {
        self.resolved = storage.allSatisfy { $0.resolved }
        self.invariant = storage.first(where: {!$0.invariant}) != nil
        self.storage.forEach { symbols.formUnion($0.symbols) }
    }
    
    /// Return the Expression and Operator Forms if the array of Parameters forms a syntactically correct Expression
    private static func expressible(_ p: [LeafParameter]) -> ContainerForm? {
        let op: LeafOperator
        let opForm: LeafOperator.Form
        guard p.count == 2 || p.count == 3 else { return nil }
        
        if p.count == 3 {
            if let o = infixExp(p[0], p[1], p[2]), o.parseable { op = o; opForm = .infix }
            else { return nil }
        } else {
            if let o = unaryPreExp(p[0], p[1]), o.parseable { op = o; opForm = .unaryPrefix }
            else if let o = unaryPostExp(p[0], p[1]), o.parseable { op = o; opForm = .unaryPostfix }
            else { return nil }
        }
        // Ignore special case of prefix minus here
        if op.mathematical || op.logical { return (.calculation, opForm) }
        else if [.subScript, .nilCoalesce].contains(op) { return (.calculation, .infix) }
        else { return (.assignment, opForm) }
    }
    
    /// Return the operator if the three parameters are syntactically an infix expression
    private static func infixExp(_ a: LeafParameter, _ b: LeafParameter, _ c: LeafParameter) -> LeafOperator? {
        guard let op = b.operator, op.infix,
              a.operator == nil, c.operator == nil else { return nil }
        return op
    }
    
    /// Return the operator if the two parameters is syntactically a unaryPrefix expression
    private static func unaryPreExp(_ a: LeafParameter, _ b: LeafParameter) -> LeafOperator? {
        guard let op = a.operator, op.unaryPrefix, b.operator == nil else { return nil}
        return op
    }
    
    /// Return the operator if the two parameters is syntactically a unaryPostfix expression
    private static func unaryPostExp(_ a: LeafParameter, _ b: LeafParameter) -> LeafOperator? {
        guard let op = b.operator, op.unaryPostfix, a.operator == nil else { return nil}
        return op
    }
 
    /// Evaluate an infix expression
    private func evalInfix(_ lhs: LeafData, _ op: LeafOperator, _ rhs: LeafData) -> LeafData {
        assert(op.infix && op.parseable, "`evalInfix` called on non-infix expression")
                        
        switch op {
            case .nilCoalesce    : return lhs.isNil ? rhs : lhs
            // Equatable conformance passthrough
            case .equal          : return .bool(lhs == rhs)
            case .unequal        : return .bool(lhs != rhs)
            // If data is bool-representable, that value; other wise true if non-nil
            case .and, .or, .xor :
                let lhsB = lhs.bool ?? !lhs.isNil
                let rhsB = rhs.bool ?? !rhs.isNil
                if op == .and { return .bool(lhsB && rhsB) }
                if op == .xor { return .bool(lhsB != rhsB) }
                return .bool(lhsB || rhsB)
            // Int compare when both int, Double compare when both numeric & >0 Double
            // String compare when neither a numeric type
            case .greater, .lesserOrEqual, .lesser, .greaterOrEqual  :
                return .bool(comparisonOp(op, lhs, rhs))
            // If both sides are numeric, use lhs to indicate return type and sum
            // If left side is string, concatanate string
            // If left side is data, concatanate data
            // If both sides are collections of same type -
            //      If array, concatenate
            //      If dictionary and no keys overlap, concatenate
            // If left side is array, append rhs as single value
            // Anything else fails
            case .plus           :
                if lhs.state.intersection(rhs.state).contains(.numeric) {
                    guard let numeric = numericOp(op, lhs, rhs) else { fallthrough }
                    return numeric
                } else if lhs.celf == .string {
                    return .string(lhs.string! + (rhs.string ?? ""))
                } else if lhs.celf == .data {
                    return .data(lhs.data! + (rhs.data ?? Data()))
                } else if !lhs.state.intersection(rhs.state)
                                    .intersection([.celfMask, .collection])
                                    .contains(.void) {
                    if lhs.celf == .array { return .array(lhs.array! + rhs.array!) }
                    guard let lhs = lhs.dictionary, let rhs = rhs.dictionary,
                          Set(lhs.keys).intersection(Set(rhs.keys)).isEmpty else { fallthrough }
                    return .dictionary(lhs.merging(rhs) {old, _ in old })
                } else if lhs.celf == .array {
                    return .array(lhs.array! + [rhs])
                } else if rhs.celf == .string {
                    return .string((lhs.string ?? "") + rhs.string!)
                } else { return .trueNil }
            case .minus, .divide, .multiply, .modulo :
                if lhs.state.intersection(rhs.state).contains(.numeric) {
                    guard let numeric = numericOp(op, lhs, rhs) else { fallthrough }
                    return numeric
                } else { fallthrough }
            case .subScript:
                if lhs.celf == .array, let index = rhs.int,
                   case .array(let a) = lhs.container,
                   a.indices.contains(index) { return a[index] }
                if lhs.celf == .dictionary, let key = rhs.string,
                   case .dictionary(let d) = lhs.container { return d[key] ?? .trueNil }
                fallthrough
            default: return .trueNil
        }
        
    }
    
    /// Evaluate a prefix expression
    private func evalPrefix(_ op: LeafOperator, _ rhs: LeafData) -> LeafData {
        assert(op.unaryPrefix && op.parseable, "`evalPrefix` called on non-prefix expression")
       
        switch op {
            // nil == false; ergo !nil == true
            case .not   : return .bool(!(rhs.bool ?? false))
            // raw Int & Double only - don't attempt to cast
            case .minus :
                if case .int(let i) = rhs.container { return .int(-1 * i) }
                else if case .double(let d) = rhs.container { return .double(-1 * d) }
                else { fallthrough }
            default     :  return .trueNil
        }
    }
    
    /// Evaluate a postfix expression
    private func evalPostfix(_ lhs: LeafData, _ op: LeafOperator) -> LeafData { .trueNil }
    
    /// Encapsulated calculation for `>, >=, <, <=`
    /// Nil returning unless both sides are in [.int, .double] or both are string-convertible & non-nil
    private func comparisonOp(_ op: LeafOperator, _ lhs: LeafData, _ rhs: LeafData) -> Bool? {
        if lhs.isCollection || rhs.isCollection || lhs.isNil || rhs.isNil { return nil }
        var op = op
        var lhs = lhs
        var rhs = rhs
        let numeric = lhs.container.isNumeric && rhs.container.isNumeric
        let manner = !numeric ? .string : lhs.celf == rhs.celf ? lhs.celf : .double
        if op == .lesserOrEqual || op == .greaterOrEqual {
            swap(&lhs, &rhs)
            op = op == .lesserOrEqual ? .greater : .lesser
        }
        switch   (manner ,  op     ) {
            case (.int   , .greater) : return lhs.int    ?? 0   > rhs.int    ?? 0
            case (.double, .greater) : return lhs.double ?? 0.0 > rhs.double ?? 0.0
            case (_      , .greater) : return lhs.string ?? ""  > rhs.string ?? ""
            case (.int   , .lesser ) : return lhs.int    ?? 0   < rhs.int    ?? 0
            case (.double, .lesser ) : return lhs.double ?? 0.0 < rhs.double ?? 0.0
            case (_      , .lesser ) : return lhs.string ?? ""  < rhs.string ?? ""
            default                  : return nil
        }
    }
    
    /// Encapsulated calculation for `+, -, *, /, %`
    /// Nil returning unless both sides are in [.int, .double]
    private func numericOp(_ op: LeafOperator, _ lhs: LeafData, _ rhs: LeafData) -> LeafData? {
        guard lhs.state.intersection(rhs.state).contains(.numeric) else { return nil }
        if lhs.celf == .int {
            guard let lhsI = lhs.int, let rhsI = rhs.convert(to: .int, .coercible).int else { return nil }
            let value: (partialValue: Int, overflow: Bool)
            switch op {
                case .plus     : value = lhsI.addingReportingOverflow(rhsI)
                case .minus    : value = lhsI.subtractingReportingOverflow(rhsI)
                case .multiply : value = lhsI.multipliedReportingOverflow(by: rhsI)
                case .divide   : value = lhsI.dividedReportingOverflow(by: rhsI)
                case .modulo   : value = lhsI.remainderReportingOverflow(dividingBy: rhsI)
                default        : return nil
            }
            guard value.overflow == false else { return nil }
            return .int(value.partialValue)
        } else {
            guard let lhsD = lhs.double, let rhsD = rhs.double else { return nil }
            switch op {
                case .plus     : return .double(lhsD + rhsD)
                case .minus    : return .double(lhsD - rhsD)
                case .multiply : return .double(lhsD * rhsD)
                case .divide   : return .double(lhsD / rhsD)
                case .modulo   : return .double(lhsD.remainder(dividingBy: rhsD))
                default: return nil
            }
        }
    }
}
