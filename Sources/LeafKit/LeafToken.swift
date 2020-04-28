public enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`, `yes`, `no`
    
    var isBooleanValued: Bool {
        switch self {
            case .true,
                 .false
                 : return true
            default: return false
        }
    }
    
    var booleanValue: Bool? {
        switch self {
            case .true: return true
            case .false: return false
            default: return nil
        }
    }
}

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
    
    public var description: String { return rawValue }
}

extension Operator {
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
    
    var isBinary: Bool {
        switch self {
            case .not: return false
            default: return true
        }
    }
    
    var isUnaryPrefix: Bool {
        switch self {
            case .not: return true
            default: return false
        }
    }
}

public enum Constant: CustomStringConvertible, Equatable {
    case int(Int)
    case double(Double)
    
    public var description: String {
        switch self {
            case .int(let i): return i.description
            case .double(let d): return d.description
        }
    }
}

public indirect enum ParameterDeclaration: CustomStringConvertible {
    case parameter(Parameter)
    case expression([ParameterDeclaration])
    case tag(Syntax.CustomTagDeclaration)
    
    public var description: String {
        switch self {
        case .parameter(let p):
            return p.description
        case .expression(let p):
            return name + "(" + p.map { $0.short }.joined(separator: " ") + ")"
        case .tag(let tag):
            return "tag(" + tag.name + ": " + tag.params.map { $0.short } .joined(separator: ",") + ")"
        }
    }
    
    var short: String {
        switch self {
        case .parameter(let p):
            return p.short
        case .expression(let p):
            return "[\(p.map { $0.short }.joined(separator: " "))]"
        case .tag(let tag):
            return tag.name + "(" + tag.params.map { $0.short }.joined(separator: " ") + ")"
        }
    }
    
    var name: String {
        switch self {
        case .parameter:
            return "parameter"
        case .expression:
            return "expression"
        case .tag:
            return "tag"
        }
    }
}

public indirect enum Parameter: Equatable, CustomStringConvertible {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(name: String)
    
    // case
    public var description: String {
        return name + "(" + short + ")"
    }
    
    var name: String {
        switch self {
        case .stringLiteral:
            return "stringLiteral"
        case .constant:
            return "constant"
        case .variable:
            return "variable"
        case .keyword:
            return "keyword"
        case .operator:
            return "operator"
        case .tag:
            return "tag"
        }
    }
    
    var short: String {
        switch self {
        case .stringLiteral(let s):
            return "\"\(s)\""
        case .constant(let c):
            return "\(c)"
        case .variable(let v):
            return "\(v)"
        case .keyword(let k):
            return "\(k)"
        case .operator(let o):
            return "\(o)"
        case .tag(let t):
            return "\"\(t)\""
        }
    }
}

public enum LeafToken: CustomStringConvertible, Equatable  {
    
    case raw(String)
    
    case tagIndicator
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parameter(Parameter)
    case parametersEnd
    
    // TODO: RM IF POSSIBLE
    case stringLiteral(String)
    case whitespace(length: Int)
    
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
        if case .parameter(let p) = lhs, case .operator = p { return }
        if case .parameter(let p) = rhs, case .operator = p { return }
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
            if let op = pD.operator() {
                return check(op) ? count + 1 : count
            }
            return count
        })
    }
    
    func findLastOpWhere(_ check: (Operator) -> Bool) -> Int? {
        for (index, pD) in self.enumerated().reversed() {
            if let op = pD.operator(), check(op) { return index }
        }
        return nil
    }
}
