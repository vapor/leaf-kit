enum LeafSyntax: CustomStringConvertible {
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
    
    case raw(ByteBuffer)
    case tag(Tag)
    case variable(Variable)
    case endTag(String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return string.debugDescription
        case .tag(let tag):
            return tag.description
        case .variable(let variable):
            return variable.description
        case .endTag(let name):
            return "#end\(name)"
        }
    }
}

struct LeafParser {
    private let tokens: [LeafToken]
    private var offset: Int
    
    init(tokens: [LeafToken]) {
        self.tokens = tokens
        self.offset = 0
    }
    
    mutating func parse() throws -> [LeafSyntax] {
        var ast: [LeafSyntax] = []
        while let next = try self.next() {
            ast.append(next)
        }
        return ast
    }
    
    mutating func next() throws -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let name):
            self.pop()
            return self.nextTag(named: name)
                .map { .tag($0) }
        default:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextTag(named name: String) -> LeafSyntax.Tag? {
        guard let peek = self.peek() else {
            return nil
        }
        var parameters: [LeafSyntax] = []
        switch peek {
        case .parametersStart:
            self.pop()
            while let parameter = self.nextParameter() {
                parameters.append(parameter)
            }
        case .tagBodyIndicator:
            // will be handled below
            break
        default: fatalError("unexpected token: \(peek)")
        }
        
        if self.peek() == .tagBodyIndicator {
            self.pop()
            var body: [LeafSyntax] = []
            while let next = self.nextTagBody(named: name) {
                body.append(next)
            }
            return .init(name: name, parameters: parameters, body: body)
        } else {
            return .init(name: name, parameters: parameters, body: nil)
        }
        
    }
    
    mutating func nextTagBody(named parentName: String) -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let subName):
            self.pop()
            if subName == "end" + parentName {
                return nil
            } else {
                return self.nextTag(named: subName)
                    .map { .tag($0) }
            }
        default: fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextParameter() -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        switch peek {
        case .variable(let name):
            self.pop()
            return .variable(.init(name: name))
        case .parameterDelimiter:
            self.pop()
            return self.nextParameter()
        case .parametersEnd:
            self.pop()
            return nil
        default:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    func peek() -> LeafToken? {
        guard self.offset < self.tokens.count else {
            return nil
        }
        return self.tokens[self.offset]
    }
    
    mutating func pop() {
        self.offset += 1
    }
}

