enum LeafToken: CustomStringConvertible, Equatable  {
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
    
    case raw(ByteBuffer)
    
    case tagIndicator
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parametersEnd
    
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case constant(Constant)
    
    case stringLiteral(String)
    
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
        case .variable(let name):
            return "variable(name: \(name.debugDescription))"
        case .constant(let const):
            return "constant(\(const))"
        case .keyword(let key):
            return "keyword(\(key.rawValue))"
        case .operator(let op):
            return "operator(\(op.rawValue))"
        case .stringLiteral(let string):
            return "stringLiteral(\(string.debugDescription))"
        }
    }
}
