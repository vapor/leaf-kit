var customTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
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
        case .expression(let exp):
            try serialize(expression: exp)
        case .import, .extend, .export:
            throw "syntax \(syntax) should have been resolved BEFORE serialization"
        }
    }

    mutating func serialize(expression: [ParameterDeclaration]) throws {
        let resolver = ParameterResolver(params: [.expression(expression)], data: data)
        let resolved = try resolver.resolve()
        guard resolved.count == 1 else { throw "expressions should resolve to single value" }
        let data = resolved[0].result
        serialize(data)
    }

    mutating func serialize(body: [Syntax]) throws {
        try body.forEach { try serialize($0) }
    }
    
    mutating func serialize(_ conditional: Syntax.Conditional) throws {
        let list: [ParameterDeclaration]
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
        let satisfied = try resolver.resolve().map { $0.result.bool ?? !$0.result.isNull } .reduce(true) { $0 && $1 }
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
        let data: LeafData
        switch variable.path.count {
        case 0: data = .null
        case 1: data = self.data[variable.path[0]] ?? .null
        default:
            var current = self.data[variable.path[0]] ?? .null
            var iterator = variable.path.dropFirst().makeIterator()
            while let path = iterator.next() {
                current = current.dictionary?[path] ?? .null
            }
            data = current
        }
        self.serialize(data)
    }
    
    mutating func serialize(_ loop: Syntax.Loop) throws {
        let finalData: [String: LeafData]
        let pathComponents = loop.array.split(separator: ".")
        
        if pathComponents.count > 1 {
            finalData = try pathComponents[0..<(pathComponents.count - 1)].enumerated()
                .reduce(data) { (innerData, pathContext) -> [String: LeafData] in
                    let key = String(pathContext.element)
                    
                    guard let nextData = innerData[key]?.dictionary else {
                        let currentPath = pathComponents[0...pathContext.offset].joined(separator: ".")
                        throw "expected dictionary at key: \(currentPath)"
                    }
                    
                    return nextData
                }
        } else {
            finalData = data
        }
        
        guard let array = finalData[String(pathComponents.last!)]?.array else {
            throw "expected array at key: \(loop.array)"
        }
        
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
        if let raw = data.data {
            self.buffer.writeBytes(raw)
        } else if let raw = data.string {
            self.buffer.writeString(raw)
        } else {
            return
        }
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
