// MARK: `LeafToken` Summary

/// `LeafToken` represents the first stage of parsing Leaf templates - a raw file/bytestream `String`
/// will be read by `LeafLexer` and interpreted into `[LeafToken]` representing a stream of tokens.
///
/// # STABLE TOKEN DEFINITIONS
/// - `.raw`: A variable-length string of data that will eventually be output directly without processing
/// - `.tagIndicator`: The signal at top-level that a Leaf syntax object will follow. Default is `#` and
///     while it can be configured to be something else, only rare uses cases may want to do so.
///     `.tagindicator` can be escaped in source templates with a backslash and will automatically
///     be consumed by `.raw` if so. May decay to `.raw` at the token parsing stage if a non-
///     tag/syntax object follows.
/// - `.tag`: The expected tag name - in `#for(index in array)`, equivalent token is `.tag("for")`
/// - `.tagBodyIndicator`: Indicates the start of a body-bearing tag - ':'
/// - `.parametersStart`: Indicates the start of a tag's parameters - `(`
/// - `.parameterDelimiter`: Indicates a delimter between parameters - `,`
/// - `.parameter`: Associated value enum storing a valid tag parameter.
/// - `.parametersEnd`: Indicates the end of a tag's parameters - `)`
///
/// # POTENTIALLY UNSTABLE TOKENS
/// - `.stringLiteral`: Does not appear to be used anywhere?
/// - `.whitespace`: Only generated when not at top-level, and unclear why maintaining it is useful
///
/// # TODO
/// - LeafTokens would ideally also store the range of their location in the original source template

public enum LeafToken: CustomStringConvertible, Equatable  {
    /// Holds a variable-length string of data that will be passed through with no processing
    case raw(String)
    
    /// `#` (or as configured) - Top-level signal that indicates a Leaf tag/syntax object will follow.
    case tagIndicator
    /// Holds the name of an expected tag or syntax object (eg, `for`) in `#for(index in array)`
    case tag(name: String)
    /// `:` - Indicates the start of a body for a body-bearing tag
    case tagBodyIndicator

    /// `(` -  Indicates the start of a tag's parameters
    case parametersStart
    /// `,` -  Indicates separation of a tag's parameters
    case parameterDelimiter
    /// Holds a `Parameter` enum
    case parameter(Parameter)
    /// `)` -  Indicates the end of a tag's parameters
    case parametersEnd

    /// To be removed if possible - avoid using
    case stringLiteral(String)
    /// To be removed if possible - avoid using
    case whitespace(length: Int)
    
    /// Returns `"tokenCase"` or `"tokenCase(valueAsString)"` if holding a value
    public var description: String {
        switch self {
            case .raw(let str):
                return "raw(\(str.debugDescription))"
            case .tagIndicator:
                return "tagIndicator"
            case .tag(let name):
                return "tag(name: \(name.debugDescription))"
            case .tagBodyIndicator:
                return "tagBodyIndicator"
            case .parametersStart:
                return "parametersStart"
            case .parametersEnd:
                return "parametersEnd"
            case .parameterDelimiter:
                return "parameterDelimiter"
            case .parameter(let param):
                return "param(\(param))"
            case .stringLiteral(let string):
                return "stringLiteral(\(string.debugDescription))"
            case .whitespace(let length):
                return "whitespace(\(length))"
        }
    }
}

// MARK: - `Parameter` Token Type

/// An associated value enum holding data, objects or values usable as parameters to a `.tag`
///
/// # TODO
/// - This doesn't appear to need to be an indirect.
/// - Does `stringLiteral` need to exist - should `Constant` have a `String` case or should
///   `Constant` be renamed `Numeric` for clarity?
public indirect enum Parameter: Equatable, CustomStringConvertible {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(name: String)
    
    /// Returns `parameterCase(parameterValue)`
    public var description: String {
        return name + "(" + short + ")"
    }
    
    /// Returns `parameterCase`
    var name: String {
        switch self {
            case .stringLiteral: return "stringLiteral"
            case .constant:      return "constant"
            case .variable:      return "variable"
            case .keyword:       return "keyword"
            case .operator:      return "operator"
            case .tag:           return "tag"
        }
    }
    
    /// Returns `parameterValue` or `"parameterValue"` as appropriate for type
    var short: String {
        switch self {
            case .stringLiteral(let s): return "\"\(s)\""
            case .constant(let c):      return "\(c)"
            case .variable(let v):      return "\(v)"
            case .keyword(let k):       return "\(k)"
            case .operator(let o):      return "\(o)"
            case .tag(let t):           return "\"\(t)\""
        }
    }
}

// MARK: - `Parameter`-Storable Types

/// `Keyword`s are dentifiers which take precedence over syntax/variable names - may potentially have
/// representable state themselves as value when used with operators (eg, `true`, `false` when
/// used with logical operators, `nil` when used with equality operators, and so forth)
public enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`, `yes`, `no`
}

/// Mathematical and Logical operators
public enum Operator: String, Equatable, CustomStringConvertible {
    case not = "!"
    case equals = "=="
    case notEquals = "!="
    case greaterThan = ">"
    case greaterThanOrEquals = ">="
    case lessThan = "<"
    case lessThanOrEquals = "<="

    case plus = "+"
    case minus = "-"
    case divide = "/"
    case multiply = "*"

    case and = "&&"
    case or = "||"
    
    /// Raw string value of the operator - eg `!=`
    public var description: String { return rawValue }
}

/// An integer or double constant value parameter (eg `1_000`, `-42.0`)
///
/// #TODO
/// - This is somewhat confusingly named. Possibly would be better to rename as `Numeric`, since
///   `stringLiteral` *IS* a constant type, or else `stringLiteral` should be moved into this.
public enum Constant: CustomStringConvertible, Equatable {
    case int(Int)
    case double(Double)

    public var description: String {
        switch self {
            case .int(let i):    return i.description
            case .double(let d): return d.description
        }
    }
}

// MARK:- --- THIS SECTION TO BE MOVED TO A NEW FILE ---
/// `ParameterDeclaration is NOT used at the lexing stage and is not presentable as a LeafToken - it
/// is built and interpreted during LeafParser.parse(). Move to a more appropriate file.

public indirect enum ParameterDeclaration: CustomStringConvertible {
    case parameter(Parameter)
    case expression([ParameterDeclaration])
    case tag(Syntax.CustomTagDeclaration)

    public var description: String {
        switch self {
            case .parameter(let p): return p.description
            case .expression(_):    return self.short
            case .tag(let t):       return "tag(\(t.name): \(t.params.describe(",")))"
        }
    }

    var short: String {
        switch self {
            case .parameter(let p):  return p.short
            case .expression(let p): return "[\(p.describe())]"
            case .tag(let t):        return "\(t.name)(\(t.params.describe(",")))"
        }
    }

    var name: String {
        switch self {
            case .parameter:  return "parameter"
            case .expression: return "expression"
            case .tag:        return "tag"
        }
    }
    
    internal func imports() -> Set<String> {
        switch self {
            case .parameter(_): return .init()
            case .expression(let e): return e.imports()
            case .tag(let t):
                guard t.name == "import" else { return t.imports() }
                guard let parameter = t.params.first,
                      case .parameter(let p) = parameter,
                      case .stringLiteral(let key) = p,
                      !key.isEmpty else { return .init() }
                return .init(arrayLiteral: key)
        }
    }
    
    internal func inlineImports(_ imports: [String : Syntax.Export]) -> ParameterDeclaration {
        switch self {
            case .parameter(_): return self
            case .tag(let t):
                guard t.name == "import" else {
                    return .tag(.init(name: t.name, params: t.params.inlineImports(imports)))
                }
                guard let parameter = t.params.first,
                      case .parameter(let p) = parameter,
                      case .stringLiteral(let key) = p,
                      let export = imports[key]?.body.first,
                      case .expression(let exp) = export,
                      exp.count == 1,
                      let e = exp.first else { return self }
                return e                    
            case .expression(let e):
                guard !e.isEmpty else { return self }
                return .expression(e.inlineImports(imports))
        }
    }
}

internal extension Array where Element == ParameterDeclaration {
    // evaluate a flat array of Parameters ("Expression")
    // returns true if the expression was reduced, false if
    // not or if unreducable (eg, non-flat or no operands).
    // Does not promise that the resulting Expression is valid.
    // This is brute force and not very efficient.
    @discardableResult mutating func evaluate() -> Bool {
        // Expression with no operands can't be evaluated
        var ops = operandCount()
        guard ops > 0 else { return false }
        // check that the last param isn't an op, this is not resolvable
        // since there are no unary postfix options currently
        guard last?.operator() == nil else { return false }

        // Priority:
        // Unary: Not
        // Binary Math: Mult/Div -> Plus/Minus
        // Binary Boolean: >/>=/<=/< -> !=/== -> &&/||
        let precedenceMap: [(check: ((Operator) -> Bool) , binary: Bool)]
        precedenceMap = [
            (check: { $0 == .not } , binary: false), // unaryNot
            (check: { $0 == .multiply || $0 == .divide } , binary: true), // Mult/Div
            (check: { $0 == .plus || $0 == .minus } , binary: true), // Plus/Minus
            (check: { $0 == .greaterThan || $0 == .greaterThanOrEquals } , binary: true), // >, >=
            (check: { $0 == .lessThan || $0 == .lessThanOrEquals } , binary: true), // <, <=
            (check: { $0 == .equals || $0 == .notEquals } , binary: true), // !, !=
            (check: { $0 == .and || $0 == .or } , binary: true), // &&, ||
        ]

        groupOps: for map in precedenceMap {
            while let i = findLastOpWhere(map.check) {
                if map.binary { wrapBinaryOp(i)}
                else { wrapUnaryNot(i) }
                // Some expression could not be wrapped - probably malformed syntax
                if ops == operandCount() { return false } else { ops -= 1 }
                if operandCount() == 0 { break groupOps }
            }
        }

        flatten()
        return ops > 1 ? true : false
    }

    mutating func flatten() {
        while count == 1 {
            if case .expression(let e) = self.first! {
                self.removeAll()
                self.append(contentsOf: e)
            } else { return }
        }
        return
    }

    fileprivate mutating func wrapUnaryNot(_ i: Int) {
        let rhs = remove(at: i + 1)
        if case .parameter(let p) = rhs, case .keyword(let key) = p, key.isBooleanValued {
            self[i] = .parameter(.keyword(Keyword(rawValue: String(!key.booleanValue!))!))
        } else {
            self[i] = .expression([self[i],rhs])
        }
    }

    // could be smarter and check param types beyond verifying non-op but we're lazy here
    fileprivate mutating func wrapBinaryOp(_ i: Int) {
        // can't wrap unless there's a lhs and rhs
        guard self.indices.contains(i-1),self.indices.contains(i+1) else { return }
        let lhs = self[i-1]
        let rhs = self[i+1]
        // can't wrap if lhs or rhs is an operator
        if case .parameter(.operator) = lhs { return }
        if case .parameter(.operator) = rhs { return }
        self[i] = .expression([lhs, self[i], rhs])
        self.remove(at:i+1)
        self.remove(at:i-1)
    }

    // Helper functions
    func operandCount() -> Int { return reduceOpWhere { _ in true } }
    func unaryOps() -> Int { return reduceOpWhere { $0.isUnaryPrefix } }
    func binaryOps() -> Int { return reduceOpWhere { $0.isBinary } }
    func reduceOpWhere(_ check: (Operator) -> Bool) -> Int {
        return self.reduce(0, { count, pD  in
            return count + (pD.operator().map { check($0) ? 1 : 0 } ?? 0)
        })
    }

    func findLastOpWhere(_ check: (Operator) -> Bool) -> Int? {
        for (index, pD) in self.enumerated().reversed() {
            if let op = pD.operator(), check(op) { return index }
        }
        return nil
    }
    
    func describe(_ joinBy: String = " ") -> String {
        return self.map {$0.short }.joined(separator: joinBy)
    }
    
    func imports() -> Set<String> {
        var result = Set<String>()
        self.forEach { result.formUnion($0.imports()) }
        return result
    }
    
    func inlineImports(_ imports: [String : Syntax.Export]) -> [ParameterDeclaration] {
        guard !self.isEmpty else { return self }
        guard !imports.isEmpty else { return self }
        return self.map { $0.inlineImports(imports) }
    }
    
    func atomicRaw() -> Syntax? {
        // only atomic expressions can be converted
        guard self.count < 2 else { return nil }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        // empty expressions = empty raw
        guard self.count == 1 else { return .raw(buffer) }
        // only single value parameters can be converted
        guard case .parameter(let p) = self[0] else { return nil }
        switch p {
            case .constant(let c): buffer.writeString(c.description)
            case .keyword(let k): buffer.writeString(k.rawValue)
            case .operator(let o): buffer.writeString(o.rawValue)
            case .stringLiteral(let s): buffer.writeString(s)
            // .tag, .variable not atomic
            default: return nil
        }
        return .raw(buffer)
    }
}
// MARK: --- END OF SECTION TO BE MOVED ---

// MARK: - Observational Helper Extensions to `Parameter` Types

extension Keyword {
    /// Whether a `Keyword`  can be interpreted as a Boolean values
    var isBooleanValued: Bool {
        switch self {
            case .true,
                 .false,
                 .yes,
                 .no: return true
            default:  return false
        }
    }
    
    /// For `Keyword`s which can be interpreted as Boolean values, return that value or nil
    var booleanValue: Bool? {
        switch self {
            case .true, .yes: return true
            case .false, .no: return false
            default:          return nil
        }
    }
}

extension Operator {
    /// Whether an operator is a logical operator (ie, takes `Bool` values
    var isBoolean: Bool {
        switch self {
            case .not,
                 .equals,
                 .notEquals,
                 .greaterThan,
                 .greaterThanOrEquals,
                 .lessThan,
                 .lessThanOrEquals,
                 .and,
                 .or:
                return true
            default:
                return false
        }
    }
    
    /// Whether an operator is a binary operator (ie, takes both LHS and RHS arguments)
    var isBinary: Bool {
        switch self {
            case .not: return false
            default:   return true
        }
    }
    
    /// Whether an operator is a unary prefix operator (ie, takes only a RHS argument)
    var isUnaryPrefix: Bool {
        switch self {
            case .not: return true
            default:   return false
        }
    }
}
