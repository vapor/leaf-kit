indirect enum LeafSyntax: CustomStringConvertible {
    struct Variable: CustomStringConvertible {
        var name: String
        
        var description: String {
            return self.name
        }
    }
    
    struct Tag: CustomStringConvertible {
        var name: String
        var parameters: [LeafSyntax]
        var body: [LeafSyntax]?
        
        var description: String {
            let params = self.parameters.map { $0.description }.joined(separator: ", ")
            if let body = body {
                let b = body.map { $0.description }.joined(separator: ", ")
                return "#\(self.name)(\(params)) { \(b) }"
            } else {
                return "#\(self.name)(\(params))"
            }
        }
    }
    
    struct Conditional: CustomStringConvertible {
        var condition: LeafSyntax
        var body: [LeafSyntax]
        var next: LeafSyntax?
        
        var description: String {
            let b = body.map { $0.description }.joined(separator: ", ")
            if let next = self.next {
                return "#if(\(self.condition)) { \(b) } \(next.description)"
            } else {
                return "#if(\(self.condition)) { \(b) }"
            }
        }
    }
    
    enum Constant: CustomStringConvertible {
        case bool(Bool)
        case string(String)
        
        var description: String {
            switch self {
            case .bool(let bool): return bool.description
            case .string(let string): return string.debugDescription
            }
        }
    }
    
    case raw(ByteBuffer)
    case tag(Tag)
    case conditional(Conditional)
    case variable(Variable)
    case constant(Constant)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return string.debugDescription
        case .tag(let tag):
            return tag.description
        case .variable(let variable):
            return variable.description
        case .conditional(let conditional):
            return conditional.description
        case .constant(let constant):
            return constant.description
        }
    }
}
