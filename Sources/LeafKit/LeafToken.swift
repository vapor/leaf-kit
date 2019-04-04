public enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`, `yes`, `no`
}

public enum Operator: String, Equatable, CustomStringConvertible {
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
    var isBooleanOperator: Bool {
        switch self {
        case .equals,
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
            return p.map { $0.short }.joined(separator: " ")
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

enum LeafToken: CustomStringConvertible, Equatable  {
    
    case raw(String)
    
    case tagIndicator
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parameter(Parameter)
    case parametersEnd
    
    // TODO: RM IF POASIBLE
    case stringLiteral(String)
    case whitespace(length: Int)
    
    var description: String {
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
