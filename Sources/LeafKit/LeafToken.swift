enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`
}

enum Operator: String, Equatable {
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

indirect enum Parameter: Equatable {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(name: String)
    case expression([Parameter])
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
    
//    case variable(name: String)
//    case keyword(Keyword)
//    case `operator`(Operator)
//    case constant(Constant)
    
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
