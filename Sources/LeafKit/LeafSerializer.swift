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
    private let ast: [Syntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private var context: [String: TemplateData]
    
    init(ast: [Syntax], context: [String: TemplateData]) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.context = context
    }
    
    mutating func serialize() throws -> ByteBuffer {
        self.offset = 0
        while let next = self.peek() {
            self.pop()
            try self.serialize(next)
        }
        return self.buffer
    }
    
    mutating func serialize(_ syntax: Syntax) throws {
        switch syntax {
        case .raw(var byteBuffer):
            self.buffer.writeBuffer(&byteBuffer)
        case .variable(let v):
            self.serialize(v)
        case .custom(let custom):
            self.serialize(custom)
        case .conditional(let c):
            self.serialize(c)
        case .loop(let loop):
            try self.serialize(loop)
        case .import, .extend, .export:
            throw "syntax \(syntax) should have been resolved BEFORE serialization"
        }
    }
    
    mutating func serialize(_ conditional: Syntax.Conditional) {
        fatalError()
    }
    
    mutating func serialize(_ tag: Syntax.CustomTag) {
        fatalError()
    }
    
    mutating func serialize(_ variable: Syntax.Variable) {
        guard let data = self.context[variable.name] else {
            fatalError("no variable named \(variable.name)")
        }
        self.serialize(data)
    }
    
    mutating func serialize(_ loop: Syntax.Loop) throws {
        guard let array = context[loop.array]?.array else { throw "expected array at key: \(loop.array)" }
        for (idx, item) in array.enumerated() {
            var innerContext = self.context
            
            if idx == 0 { innerContext["isFirst"] = .bool(true) }
            else if idx == array.count - 1 { innerContext["isLast"] = .bool(true) }
            innerContext[loop.item] = item
            
            var serializer = LeafSerializer(ast: loop.body, context: innerContext)
            var loopBody = try serializer.serialize()
            self.buffer.writeBuffer(&loopBody)
        }
    }
    
    mutating func serialize(_ data: TemplateData) {
        // todo: should throw?
        guard let raw = data.data else { return }
        self.buffer.writeBytes(raw)
    }
    
    
    func boolify(_ syntax: Syntax) -> Bool? {
        switch syntax {
        case .variable(let variable):
            if let data = self.context[variable.name] {
                return self.boolify(data)
            } else {
                return false
            }
//        case .constant(let constant):
//            switch constant {
//            case .bool(let bool): return bool
//            case .string(let string):
//                switch string {
//                case "false", "0": return false
//                default: return true
//                }
//            }
        default: fatalError()
        }
    }
    
    func boolify(_ data: TemplateData) -> Bool? {
        return data.bool ?? false
    }
    
    func peek() -> Syntax? {
        guard self.offset < self.ast.count else {
            return nil
        }
        return self.ast[self.offset]
    }
    
    mutating func pop() {
        self.offset += 1
    }
}
