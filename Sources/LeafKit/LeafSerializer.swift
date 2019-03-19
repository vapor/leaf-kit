var customTags: [String: LeafTag] = [
    "lowercased" : Lowercased(),
]

struct LeafSerializer {
    private let ast: [Syntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private var data: [String: LeafData]
    
    init(ast: [Syntax], context: [String: LeafData]) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.data = context
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
            try self.serialize(custom)
        case .conditional(let c):
            try self.serialize(c)
        case .loop(let loop):
            try self.serialize(loop)
        case .import, .extend, .export:
            throw "syntax \(syntax) should have been resolved BEFORE serialization"
        }
    }
    
    mutating func serialize(body: [Syntax]) throws {
        try body.forEach { try serialize($0) }
    }
    
    mutating func serialize(_ conditional: Syntax.Conditional) throws {
        let list: [ProcessedParameter]
        switch conditional.condition {
        case .if(let l):
            list = l
        case .elseif(let l):
            list = l
        case .else:
            try serialize(body: conditional.body)
            return
        }
        
        let resolver = ParameterResolver(params: list, data: data)
        let satisfied = try resolver.resolve().map { $0.result.bool ?? false } .reduce(false) { $0 || $1 }
        if satisfied {
            try serialize(body: conditional.body)
        } else if let next = conditional.next {
            try serialize(next)
        }
    }
    
    mutating func serialize(_ tag: Syntax.CustomTagDeclaration) throws {
        let sub = LeafContext(params: tag.params, data: data, body: tag.body)
        let rendered = try customTags[tag.name]?.render(sub)
            ?? .init(.null)
        serialize(rendered)
    }
    
    mutating func serialize(_ variable: Syntax.Variable) {
        let data = self.data[variable.name] ?? .null
        self.serialize(data)
    }
    
    mutating func serialize(_ loop: Syntax.Loop) throws {
        guard let array = data[loop.array]?.array else { throw "expected array at key: \(loop.array)" }
        for (idx, item) in array.enumerated() {
            var innerContext = self.data
            
            if idx == 0 { innerContext["isFirst"] = .bool(true) }
            else if idx == array.count - 1 { innerContext["isLast"] = .bool(true) }
            innerContext[loop.item] = item
            
            var serializer = LeafSerializer(ast: loop.body, context: innerContext)
            var loopBody = try serializer.serialize()
            self.buffer.writeBuffer(&loopBody)
        }
    }
    
    mutating func serialize(_ data: LeafData) {
        guard let raw = data.data else { return }
        self.buffer.writeBytes(raw)
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
