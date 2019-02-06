enum LeafToken: CustomStringConvertible, Equatable  {
    case raw(ByteBuffer)
    
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parametersEnd
    
    case variable(name: String)
    
    case stringLiteral(String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
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
        case .stringLiteral(let string):
            return "stringLiteral(\(string.debugDescription))"
        }
    }
}
