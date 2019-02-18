enum LeafToken: CustomStringConvertible, Equatable  {
    enum Keyword: String {
        case `in`
    }
    
    enum Operator: String {
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
        case .keyword(let key):
            return "keyword(\(key.rawValue))"
        case .operator(let op):
            return "operator(\(op.rawValue))"
        case .stringLiteral(let string):
            return "stringLiteral(\(string.debugDescription))"
        }
    }
}
