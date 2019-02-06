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
        default:
            fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextTag(named name: String) -> LeafSyntax? {
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
        
        let hasBody: Bool
        if self.peek() == .tagBodyIndicator {
            self.pop()
            hasBody = true
        } else {
            hasBody = false
        }
        
        switch name {
        case "", "get":
            return parameters[0]
        case "if", "elseif", "else":
            return self.nextConditional(
                named: name,
                parameters: parameters
            )
        default:
            return self.nextCustomTag(
                named: name,
                parameters: parameters,
                hasBody: hasBody
            )
        }
    }
    
    mutating func nextConditional(named name: String, parameters: [LeafSyntax]) -> LeafSyntax? {
        var body: [LeafSyntax] = []
        while let next = self.nextConditionalBody() {
            body.append(next)
        }
        let next: LeafSyntax?
        if let p = self.peek(), case .tag(let a) = p, (a == "else" || a == "elseif") {
            self.pop()
            next = self.nextTag(named: a)
        } else if let p = self.peek(), case .tag(let a) = p, a == "endif" {
            self.pop()
            next = nil
        } else {
            next = nil
        }
        let parameter: LeafSyntax
        switch name {
        case "else":
            parameter = .constant(.bool(true))
        default:
            parameter = parameters[0]
        }
        return .conditional(.init(
            condition: parameter,
            body: body,
            next: next
        ))
    }
    
    mutating func nextCustomTag(named name: String, parameters: [LeafSyntax], hasBody: Bool) -> LeafSyntax? {
        let body: [LeafSyntax]?
        if hasBody {
            var b: [LeafSyntax] = []
            while let next = self.nextTagBody(endToken: "end" + name) {
                b.append(next)
            }
            body = b
        } else {
            body = nil
        }
        return .tag(.init(name: name, parameters: parameters, body: body))
    }
    
    mutating func nextConditionalBody() -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let name):
            switch name {
            case "else", "elseif", "endif":
                return nil
            default:
                self.pop()
                return self.nextTag(named: name)
            }
        default: fatalError("unexpected token: \(peek)")
        }
    }
    
    mutating func nextTagBody(endToken: String) -> LeafSyntax? {
        guard let peek = self.peek() else {
            return nil
        }
        
        switch peek {
        case .raw(let raw):
            self.pop()
            return .raw(raw)
        case .tag(let n):
            self.pop()
            if n == endToken {
                return nil
            } else {
                return self.nextTag(named: n)
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
        case .stringLiteral(let string):
            self.pop()
            return LeafSyntax.constant(.string(string))
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

