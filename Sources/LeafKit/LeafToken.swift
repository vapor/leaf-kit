enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`
}

enum Operator: String, Equatable, CustomStringConvertible {
    case equals = "=="
    case notEquals = "!="
    case greaterThan = ">"
    case greaterThanOrEquals = ">="
    case lessThan = "<"
    case lessThanOrEquals = "<="
    
    case plus = "+"
    case minus = "-"
    case plusEquals = "+="
    case minusEquals = "-="
    
    case and = "&&"
    case or = "||"
    
    var description: String { return rawValue }
}

enum Constant: CustomStringConvertible, Equatable {
    case int(Int)
    case double(Double)
    
    var description: String {
        switch self {
        case .int(let i): return i.description
        case .double(let d): return d.description
        }
    }
}

struct Expression {
    let raw: [ProcessedParameter]

    func process() {
        //
    }
}

indirect enum ProcessedParameter: CustomStringConvertible, Equatable {
    case parameter(Parameter)
    case expression([ProcessedParameter])
    case tag(name: String, params: [ProcessedParameter])
    
    var description: String {
        switch self {
        case .parameter(let p):
            return p.description
        case .expression(let p):
            return name + "(" + p.map { $0.short }.joined(separator: " ") + ")"
        case .tag(let tag, let p):
            return "tag(" + tag + ": " + p.map { $0.short } .joined(separator: ",") + ")"
        }
    }
    
    var short: String {
        switch self {
        case .parameter(let p):
            return p.short
        case .expression(let p):
            return p.map { $0.short }.joined(separator: " ")
        case .tag(let name, let p):
            return name + "(" + p.map { $0.short }.joined(separator: " ") + ")"
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

indirect enum Parameter: Equatable, CustomStringConvertible {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(name: String)
    
    // TODO: RM, NOT A TOKEN
    case expression([Parameter])
    
    // case
    var description: String {
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
        case .expression:
            return "expression"
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
        case .expression(let list):
            return list.map { $0.short } .reduce("") { $0 + ", " + $1 }
        }
    }
}

enum LeafToken: CustomStringConvertible, Equatable  {
    
    case raw(ByteBuffer)
    
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
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
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
