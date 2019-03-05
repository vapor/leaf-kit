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

var tags: [String: _CustomTagProtocol] = [:]

struct Operation {
    indirect enum Argument {
        case data(TemplateData)
        case operation(Operation)
    }
    
    indirect enum Function {
        case keyword(Keyword)
        case `operator`(Operator)
    }
    
    
    let lhs: Argument
    let rhs: Argument
    let function: Function
}

struct ResolvedParameter {
    let param: ProcessedParameter
    let result: TemplateData
}

struct ParameterResolver {
    let context: [String: TemplateData]
    let params: [ProcessedParameter]
    
    func resolve() throws -> [ResolvedParameter] {
        return try params.map(resolve)
    }
    
    private func resolve(_ param: ProcessedParameter) throws -> ResolvedParameter {
        let result: TemplateData
        switch param {
        case .expression(let e):
            result = try resolve(expression: e)
        case .parameter(let p):
            result = try resolve(param: p)
        case .tag(let t):
            result = try tags[t.name]?.render(params: t.params, body: t.body, context: context)
                ?? .init(.null)
        }
        return .init(param: param, result: result)
    }
    
    private func resolve(param: Parameter) throws -> TemplateData {
        switch param {
        case .constant(let c):
            switch c {
            case .double(let d): return TemplateData(.double(d))
            case .int(let d): return TemplateData(.int(d))
            }
        case .stringLiteral(let s):
            return .init(.string(s))
        case .variable(let v):
            return context[v] ?? .init(.null)
        case .keyword(let k):
            switch k {
            case .self: return .init(.dictionary(context))
            case .nil: return .init(.null)
            case .true, .yes: return .init(.bool(true))
            case .false, .no: return .init(.bool(false))
            default: throw "unexpected keyword"
            }
        // these should all have been removed in processing
        case .tag: throw "unexpected tag"
        case .operator: throw "unexpected operator"
        case .expression: throw "unexpected expression"
        }
    }
    
    // #if(lowercase(first(name == "admin")) == "welcome")
    private func resolve(expression: [ProcessedParameter]) throws -> TemplateData {
        // todo: to support nested expressions, ie:
        // file == name + ".jpg"
        // should resolve to:
        // param(file) == expression(name + ".jpg")
        // based on priorities in such a way that each expression
        // is 3 variables, lhs, functor, rhs
        guard expression.count == 3 else { throw "multiple expressions not currently supported" }
        let lhs = try resolve(expression[0]).result
        let functor = expression[1]
        let rhs = try resolve(expression[2]).result
        guard case .parameter(let p) = functor else { throw "expected keyword or operator" }
        switch p {
        case .keyword(let k):
            return try resolve(lhs: lhs, key: k, rhs: rhs)
        case .operator(let o):
            return try resolve(lhs: lhs, op: o, rhs: rhs)
        default:
            throw "unexpected parameter: \(p)"
        }
    }
    
    private func resolve(lhs: TemplateData, op: Operator, rhs: TemplateData) throws -> TemplateData {
        switch op {
        case .and:
            let lhs = lhs.bool ?? false
            let rhs = rhs.bool ?? false
            return .init(.bool(lhs && rhs))
        case .or:
            let lhs = lhs.bool ?? false
            let rhs = rhs.bool ?? false
            return .init(.bool(lhs || rhs))
        case .equals:
            return .init(.bool(lhs == rhs))
        case .notEquals:
            return .init(.bool(lhs != rhs))
        case .lessThan:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs < rhs))
        case .lessThanOrEquals:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs <= rhs))
        case .greaterThan:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs > rhs))
        case .greaterThanOrEquals:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs >= rhs))
        case .plus, .minus, .multiply, .divide:
            fatalError("concat string, add nums")
        }
    }
    
    private func resolve(lhs: TemplateData, key: Keyword, rhs: TemplateData) throws -> TemplateData {
        switch key {
        case .in:
            let arr = rhs.array ?? []
            return .init(.bool(arr.contains(lhs)))
        default:
            return .init(.null)
        }
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
        
        let resolver = ParameterResolver(context: context, params: list)
        let satisfied = try resolver.resolve().map { $0.result.bool ?? false } .reduce(false) { $0 || $1 }
        if satisfied {
            try serialize(body: conditional.body)
        } else if let next = conditional.next {
            try serialize(next)
        }
    }
    
    mutating func serialize(_ tag: Syntax.CustomTagDeclaration) throws {
        let rendered = try tags[tag.name]?.render(params: tag.params, body: tag.body, context: context)
            ?? .init(.null)
        serialize(rendered)
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
