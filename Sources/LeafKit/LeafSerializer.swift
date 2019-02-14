public enum LeafData {
    case bool(Bool)
    case string(String)
}

extension LeafData: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension LeafData: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

struct LeafSerializer {
    private let ast: [LeafSyntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private var context: [String: LeafData]
    
    init(ast: [LeafSyntax], context: [String: LeafData]) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.context = context
    }
    
    mutating func serialize() throws -> ByteBuffer {
        self.offset = 0
        while let next = self.peek() {
            self.pop()
            self.serialize(next)
        }
        return self.buffer
    }
    
    mutating func serialize(_ syntax: LeafSyntax) {
        switch syntax {
        case .conditional(let conditional):
            self.serialize(conditional)
        case .raw(var raw):
            self.buffer.writeBuffer(&raw)
        case .tag(let tag):
            self.serialize(tag)
        case .variable(let variable):
            self.serialize(variable)
        case .constant(let constant):
            self.serialize(constant)
        case .import, .extend:
            #warning("TODO: error when serializing import / extend tags")
            break
        }
    }
    
    mutating func serialize(_ conditional: LeafSyntax.Conditional) {
        guard let shouldSerialize = self.boolify(conditional.condition) else {
            fatalError("invalid condition")
        }
        if shouldSerialize {
            conditional.body.forEach { self.serialize($0) }
        } else if let next = conditional.next {
            self.serialize(next)
        }
    }
    
    mutating func serialize(_ tag: LeafSyntax.Tag) {
        switch tag.name {
        case "get":
            switch tag.parameters.count {
            case 1: self.serialize(tag.parameters[0])
            default: fatalError()
            }
            
        default: break
        }
    }
    
    mutating func serialize(_ variable: LeafSyntax.Variable) {
        guard let data = self.context[variable.name] else {
            fatalError("no variable named \(variable.name)")
        }
        self.serialize(data)
    }
    
    mutating func serialize(_ constant: LeafSyntax.Constant) {
        switch constant {
        case .bool(let bool):
            switch bool {
            case true: self.buffer.writeString( "true")
            case false: self.buffer.writeString( "false")
            }
        case .string(let string):
            self.buffer.writeString( string)
        }
    }
    
    mutating func serialize(_ data: LeafData) {
        switch data {
        case .bool(let bool):
            switch bool {
            case true: self.buffer.writeString( "true")
            case false: self.buffer.writeString( "false")
            }
        case .string(let string): self.buffer.writeString( string)
        }
    }
    
    func boolify(_ syntax: LeafSyntax) -> Bool? {
        switch syntax {
        case .variable(let variable):
            if let data = self.context[variable.name] {
                return self.boolify(data)
            } else {
                return false
            }
        case .constant(let constant):
            switch constant {
            case .bool(let bool): return bool
            case .string(let string):
                switch string {
                case "false", "0": return false
                default: return true
                }
            }
        default: return nil
        }
    }
    
    func boolify(_ data: LeafData) -> Bool? {
        switch data {
        case .bool(let bool): return bool
        case .string(let string):
            switch string {
            case "false", "0": return false
            default: return true
            }
        }
    }
    
    func peek() -> LeafSyntax? {
        guard self.offset < self.ast.count else {
            return nil
        }
        return self.ast[self.offset]
    }
    
    mutating func pop() {
        self.offset += 1
    }
}
