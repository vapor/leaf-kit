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
        case .tagIndicator:
            self.pop()
            return try self.next()
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
            #warning("TODO: verify param count")
            return parameters[0]
        case "import":
            guard
                let parameter = parameters.first,
                case .constant(let constant) = parameter,
                case .string(let string) = constant
            else {
                fatalError("unexpected import parameter")
            }
            return .import(.init(key: string))
        case "extend":
            guard hasBody else {
                fatalError("extend must have body")
            }
            var exports: [String: [LeafSyntax]] = [:]
            while let next = self.nextTagBody(endToken: "endextend") {
                switch next {
                case .raw:
                    // ignore any raw segments
                    break
                case .tag(let tag):
                    switch tag.name {
                    case "export":
                        guard
                            let parameter = tag.parameters.first,
                            case .constant(let constant) = parameter,
                            case .string(let string) = constant
                        else {
                            fatalError("unexpected export parameter")
                        }
                        switch tag.parameters.count {
                        case 1:
                            exports[string] = tag.body!
                        case 2:
                            assert(tag.body == nil)
                            exports[string] = [tag.parameters[1]]
                        default:
                            fatalError()
                        }
                    default:
                        fatalError("Unexpected tag \(tag.name) in extend")
                    }
                default:
                    fatalError("unexpected extend syntax: \(next)")
                }
            }
            return .extend(.init(exports: exports))
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
        case .tagIndicator:
            pop()
            return self.nextConditionalBody()
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
        case .tagIndicator:
            pop()
            return nextTagBody(endToken: endToken)
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

