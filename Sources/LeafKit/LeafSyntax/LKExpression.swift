import Foundation

internal struct LKExpression: LKSymbol {
    // MARK: - Internal Only
    // MARK: - Generators

    /// Generate an LKExpression from a 2-3 value parameters that is internally resolvable
    static func express(_ params: LKParams) -> Self? { Self(params) }
    /// Generate an LKExpression from a 3 value ternary conditional
    static func expressTernary(_ params: LKParams) -> Self? { Self(ternary: params) }
    /// Generate a custom LKExpression from any 2-3 value parameters, regardless of grammar
    static func expressAny(_ params: LKParams) -> Self? { Self(custom: params) }

    // MARK: - LeafSymbol Conformance
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>

    private(set) var baseType: LKDType?

    func resolve(_ symbols: LKVarStack) -> Self {
        form.exp != .ternary
            ? .init(.init(storage.map { $0.resolve(symbols) }), form)
            : .init(.init([storage[0].resolve(symbols), storage[1], storage[2]]), form)
    }

    func evaluate(_ symbols: LKVarStack) -> LKData {
        switch form.exp {
            case .calculation : break
            case .ternary     : return evalTernary(symbols)
            case .assignment  : __MajorBug("Assignment should have redirected")
            case .custom      :
                if case .keyword(let k) = first.container,
                   k.isVariableDeclaration { return createVariable(symbols) }
                __MajorBug("Custom expression produced in AST")
        }

        let lhsData = lhs?.evaluate(symbols) ?? .trueNil
        let rhsData = rhs?.evaluate(symbols) ?? .trueNil
        switch form.op! {
            case .infix        : return evalInfix(lhsData, op!, rhsData)
            case .unaryPrefix  : return evalPrefix(op!, rhsData)
            case .unaryPostfix : return evalPostfix(lhsData, op!)
        }
    }

    /// Short String description: `lhs op rhs` for assignment/calc, `first second third?` for custom
    var short: String {
        switch form.exp {
            case .assignment,
                 .calculation: return "[\([lhs?.short ?? "", op?.short ?? "", rhs?.short ?? ""].joined(separator: " "))]"
            case .ternary: return "[\(storage[0].short) ? \(storage[1].short) : \(storage[2].short) ]"
            case .custom: return "[\(storage.compactMap { $0.operator != .subOpen ? $0.short : nil }.joined(separator: " "))]"
        }
    }
    /// String description: `expressionform[expression.short]`
    var description: String { "\(form.exp.short)\(short)" }

    // MARK: - LKExpression Specific
    /// The form expression storage takes: `[.calculation, .assignment, .ternary, .custom]`
    enum Form: String, LKPrintable {
        case calculation
        case assignment
        case ternary
        case custom

        var description: String  { rawValue }
        var short: String        { rawValue }
    }

    typealias CombinedForm = (exp: LKExpression.Form, op: LeafOperator.Form?)
    /// Reveal the form of the expression, and of the operator when expression form is relevant
    let form: CombinedForm

    /// Convenience referent name available when form is not .custom
    var op: LeafOperator?  { form.op == nil ? nil : form.op! == .unaryPrefix
                                                  ? storage[0].operator
                                                  : storage[1].operator }
    /// Convenience referent name available when form is not .custom
    var lhs: LKParameter? { [.infix, .unaryPostfix].contains(form.op) ? storage[0] : nil }
    /// Convenience referent name available when form is not .custom
    var rhs: LKParameter? { form.op == .infix ? storage[2] : form.op == .unaryPrefix ? storage[1] : nil }
    /// Convenience referent name by position within expression
    var first: LKParameter   { storage[0] }
    /// Convenience referent name by position within expression
    var second: LKParameter  { storage[1] }
    /// Convenience referent name by position within expression
    var third: LKParameter?  { storage[2].operator != .subOpen ? storage[2] : nil }
    
    
    /// If expression declares a variable, variable so declared, and value if set
    var declaresVariable: (variable: LKVariable, set: LKParameter?)? {
        if case .keyword(let k) = first.container, k.isVariableDeclaration,
           case .variable(let v) = second.container {
            let x: LKParameter?
            if case .value(.trueNil) = third?.container { x = nil } else { x = third! }
            return (v, x)
        }
        return nil
    }

    // MARK: - Private Only
    /// Actual storage of 2 or 3 Parameters
    private var storage: ContiguousArray<LKParameter> { didSet { setStates() } }

    /// Generate a `LKExpression` if possible. Guards for expressibility unless "custom" is true
    private init?(_ params: LKParams) {
        // .assignment/.calculation is failable, .custom does not check
        guard let form = Self.expressible(params) else { return nil }
        let storage = params
        // Rewrite prefix minus special case into rhs * -1
        if let unary = form.op, unary == .unaryPrefix,
           let op = params[0].operator, op == .minus {
            self = .init(.init(arrayLiteral: params[1], .operator(.multiply), .value(.int(-1))), (.calculation, .infix))
        } else { self = .init(.init(storage), form) }
    }

    /// Generate a custom `LKExpression` if possible.
    private init?(custom: LKParams) {
        guard (2...3).contains(custom.count) else { return nil }
        let storage = custom.count == 3 ? custom : custom + [.invalid]
        self = .init(.init(storage), (.custom, nil))
    }

    /// Generate a ternary `LKExpression` if possible.
    private init?(ternary: LKParams) {
        guard ternary.count == 3 else { return nil }
        self = .init(.init(ternary), (.ternary, nil))
    }

    private init(_ storage: ContiguousArray<LKParameter>, _ form: CombinedForm) {
        self.storage = storage
        self.form = form
        self.resolved = false
        self.invariant = false
        self.symbols = []
        switch form.exp {
            case .calculation : self.baseType = lhs != nil ? lhs!.baseType : rhs!.baseType
            case .ternary     : self.baseType = second.baseType == third!.baseType ? second.baseType : nil
            case .assignment  : self.baseType = op == .assignment ? rhs!.baseType : lhs!.baseType
            default           : self.baseType = nil
        }
        setStates()
    }

    private mutating func setStates() {
        resolved = storage.allSatisfy { $0.resolved }
        invariant = storage.first(where: {$0.invariant}) != nil
        // Restate variable as coalesced if operator is ??
        if storage[1].operator == .nilCoalesce {
            symbols.formUnion(rhs?.symbols ?? [])
            symbols.formUnion(lhs?.symbols.map { x in var x = x; x.state.formUnion(.coalesced); return x } ?? [])
        } else { storage.forEach { symbols.formUnion($0.symbols) } }
        
    }

    /// Return the Expression and Operator Forms if the array of Parameters forms a syntactically correct Expression
    private static func expressible(_ p: LKParams) -> CombinedForm? {
        let op: LeafOperator
        let opForm: LeafOperator.Form
        guard (2...3).contains(p.count) else { return nil }

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
    private static func infixExp(_ a: LKParameter, _ b: LKParameter, _ c: LKParameter) -> LeafOperator? {
        guard let op = b.operator, op.infix,
              a.operator == nil, c.operator == nil else { return nil }
        return op
    }

    /// Return the operator if the two parameters is syntactically a unaryPrefix expression
    private static func unaryPreExp(_ a: LKParameter, _ b: LKParameter) -> LeafOperator? {
        guard let op = a.operator, op.unaryPrefix, b.operator == nil else { return nil}
        return op
    }

    /// Return the operator if the two parameters is syntactically a unaryPostfix expression
    private static func unaryPostExp(_ a: LKParameter, _ b: LKParameter) -> LeafOperator? {
        guard let op = b.operator, op.unaryPostfix, a.operator == nil else { return nil}
        return op
    }

    /// Evaluate an infix expression
    private func evalInfix(_ lhs: LKData, _ op: LeafOperator, _ rhs: LKData) -> LKData {
        switch op {
            case .nilCoalesce    : return lhs.isNil ? rhs : lhs
            /// Equatable conformance passthrough
            case .equal          : return .bool(lhs == rhs)
            case .unequal        : return .bool(lhs != rhs)
            /// If data is bool-representable, that value; other wise true if non-nil
            case .and, .or, .xor :
                let lhsB = lhs.bool ?? !lhs.isNil
                let rhsB = rhs.bool ?? !rhs.isNil
                if op == .and { return .bool(lhsB && rhsB) }
                if op == .xor { return .bool(lhsB != rhsB) }
                return .bool(lhsB || rhsB)
            /// Int compare when both int, Double compare when both numeric & >0 Double
            /// String compare when neither a numeric type
            case .greater, .lesserOrEqual, .lesser, .greaterOrEqual  :
                return .bool(comparisonOp(op, lhs, rhs))
            /// If both sides are numeric, use lhs to indicate return type and sum
            /// If left side is string, concatanate string
            /// If left side is data, concatanate data
            /// If both sides are collections of same type -
            ///      If array, concatenate
            ///      If dictionary and no keys overlap, concatenate
            /// Anything else fails
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
    
    func createVariable(_ symbols: LKVarStack) -> LKData {
        if case .variable(let x) = second.container,
           let value = third?.container.evaluate(symbols) { symbols.create(x, value) }
        return .trueNil
    }
    
    /// Evaluate assignments.
    ///
    /// If variable lookup succeeds, return variable key and value to set to; otherwise error
    func evalAssignment(_ symbols: LKVarStack) -> Result<(LKVariable, LKData), LeafError> {
        guard case .variable(let assignor) = first.container,
              let op = op, op.assigning,
              let value = third?.evaluate(symbols) else {
            __MajorBug("Improper assignment expression") }
        
        if assignor.isPathed, let parent = assignor.parent,
           symbols.match(parent) == nil {
            return .failure(err("\(parent.short) does not exist; cannot set \(assignor)"))
        } else if !assignor.isPathed, symbols.match(assignor) == nil {
            return .failure(err("\(assignor.short) must be defined first with `var \(assignor.member ?? "")`"))
        }
        /// Straight assignment just requires identifier parent exists if it's pathed.
        if op == .assignment { return .success((assignor, value)) }
        
        guard let old = symbols.match(assignor) else {
            return .failure(err("\(assignor.member!) does not exist; can't perform compound assignment")) }
        
        let new: LKData
        switch op {
            case .compoundPlus  : new = evalInfix(old, .plus, value)
            case .compoundMinus : new = evalInfix(old, .minus, value)
            case .compoundMult  : new = evalInfix(old, .multiply, value)
            case .compoundDiv   : new = evalInfix(old, .divide, value)
            case .compoundMod   : new = evalInfix(old, .modulo, value)
            default             : __MajorBug("Unexpected operator")
        }
        return .success((assignor, new))
    }

    /// Evaluate a ternary expression
    private func evalTernary(_ symbols: LKVarStack) -> LKData {
        let condition = first.evaluate(symbols)
        switch condition.bool {
            case .some(true),
                 .none where !condition.isNil: return second.evaluate(symbols)
            case .some(false),
                 .none where condition.isNil: return third!.evaluate(symbols)
            case .none: __MajorBug("Ternary condition returned non-bool")
        }
    }

    /// Evaluate a prefix expression
    private func evalPrefix(_ op: LeafOperator, _ rhs: LKData) -> LKData {
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
    private func evalPostfix(_ lhs: LKData, _ op: LeafOperator) -> LKData { .trueNil }

    /// Encapsulated calculation for `>, >=, <, <=`
    /// Nil returning unless both sides are in [.int, .double] or both are string-convertible & non-nil
    private func comparisonOp(_ op: LeafOperator, _ lhs: LKData, _ rhs: LKData) -> Bool? {
        if lhs.isCollection || rhs.isCollection || lhs.isNil || rhs.isNil { return nil }
        var op = op
        var lhs = lhs
        var rhs = rhs
        let numeric = lhs.isNumeric && rhs.isNumeric
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
    private func numericOp(_ op: LeafOperator, _ lhs: LKData, _ rhs: LKData) -> LKData? {
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
            return value.overflow ? nil : .int(value.partialValue)
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

