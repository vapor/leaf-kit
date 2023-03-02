import NIO

internal struct LeafSerializer {
    // MARK: - Internal Only
    
    init(
        ast: [Statement],
        tags: [String: LeafTag] = defaultTags,
        userInfo: [AnyHashable: Any] = [:],
        ignoreUnfoundImports: Bool
        
    ) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.tags = tags
        self.userInfo = userInfo
        self.ignoreUnfoundImports = ignoreUnfoundImports
    }
    
    mutating func serialize(
        context data: [String: LeafData]
    ) throws -> ByteBuffer {
        for item in self.ast {
            try self.serialize(item, context: data)
        }
        return self.buffer
    }
    
    // MARK: - Private Only
    
    private let ast: [Statement]
    private var offset: Int
    private var buffer: ByteBuffer
    private let tags: [String: LeafTag]
    private let userInfo: [AnyHashable: Any]
    private let ignoreUnfoundImports: Bool

    private mutating func serialize(_ syntax: Statement, context data: [String: LeafData]) throws {
        switch syntax.kind {
            case .raw(let data):                       buffer.writeSubstring(data)
            case .conditional(let c):                  try serialize(c, context: data)
            case .forLoop(let loop):                   try serialize(loop, context: data)
            case .with(let with):                      try serialize(with, context: data)
            case .substitution(let exp):               try serialize(expression: exp, context: data)
            case .combined(let statements):            try statements.forEach { try serialize($0, context: data ) }
            case .extend(_):                           throw LeafError(.internalError(what: "extend tag should have been expanded before serialization"))
            case .import(let what):                    if ignoreUnfoundImports { break } else { throw LeafError(.importNotFound(name: String(what.name))) }
            case .export(_):                           throw LeafError(.internalError(what: "export tag should have been expanded before serialization"))
            case .tag(let name, let params, let body): try serialize(tag: String(name), params: params, body: body, context: data)
            }
    }

    private func evaluate(_ expression: Expression, context data: [String: LeafData]) throws -> LeafData {
        return try evaluateExpression(
            expression: expression,
            data: data,
            tags: tags,
            userInfo: userInfo
        )
    }

    private mutating func serialize(expression: Expression, context data: [String: LeafData]) throws {
        try evaluate(expression, context: data).htmlEscaped().serialize(buffer: &self.buffer)
    }

    private mutating func serialize(tag: String, params: [Expression]?, body: [Statement]?, context data: [String: LeafData]) throws {
        guard let tagImpl = self.tags[tag] else {
            guard (params == nil || params!.isEmpty) && body == nil else {
                throw LeafError(.tagNotFound(name: tag))
            }
            buffer.writeStaticString("#")
            buffer.writeString(tag)
            return
        }
        let params = try (params ?? []).map { try self.evaluate($0, context: data) }
        let result = try tagImpl.render(LeafContext(
            tag: tag,
            parameters: params,
            data: data,
            body: body,
            userInfo: self.userInfo
        ))
        if tagImpl is UnsafeUnescapedLeafTag {
            try result.serialize(buffer: &self.buffer)
        } else {
            try result.htmlEscaped().serialize(buffer: &self.buffer)
        }
    }

    private mutating func serialize(body: [Statement], context data: [String: LeafData]) throws {
        try body.forEach { try serialize($0, context: data) }
    }

    private mutating func serialize(_ conditional: Statement.Conditional, context data: [String: LeafData]) throws {
        let cond = try evaluate(conditional.condition, context: data)
        if cond.coerce(to: .bool) == .bool(true) {
            try serialize(body: conditional.onTrue, context: data)
        } else if cond.coerce(to: .bool) == .bool(false) {
            try serialize(body: conditional.onFalse, context: data)
        } else {
            throw LeafError(.typeError(shouldHaveBeen: .bool, got: cond.concreteType!))
        }
    }

    private mutating func serialize(_ with: Statement.With, context data: [String: LeafData]) throws {
        let evalled = try evaluate(with.context, context: data)
        guard let newData = evalled.dictionary else {
            throw LeafError(.typeError(shouldHaveBeen: .dictionary, got: evalled.concreteType!))
        }

        try? serialize(body: with.body, context: newData)
    }

    private mutating func serialize(_ loop: Statement.ForLoop, context data: [String: LeafData]) throws {
        let evalled = try evaluate(loop.inValue, context: data)
        if let array = evalled.array {
            for (idx, item) in array.enumerated() {
                var innerContext = data

                innerContext["isFirst"] = .bool(idx == array.startIndex)
                innerContext["isLast"] = .bool(idx == array.index(before: array.endIndex))
                innerContext[loop.indexName.map { String($0) } ?? "index"] = .int(idx)
                innerContext[String(loop.name)] = item

                var serializer = LeafSerializer(
                    ast: loop.body,
                    tags: self.tags,
                    userInfo: self.userInfo,
                    ignoreUnfoundImports: self.ignoreUnfoundImports
                )
                var loopBody = try serializer.serialize(context: innerContext)
                self.buffer.writeBuffer(&loopBody)
            }
        } else if let dict = evalled.dictionary {
            for idx in dict.indices {
                let item = dict[idx]

                var innerContext = data

                innerContext["isFirst"] = .bool(idx == dict.startIndex)
                innerContext["isLast"] = .bool(dict.index(after: idx) == dict.endIndex)
                innerContext[loop.indexName.map { String($0) } ?? "index"] = .string(item.key)
                innerContext[String(loop.name)] = item.value

                var serializer = LeafSerializer(
                    ast: loop.body,
                    tags: self.tags,
                    userInfo: self.userInfo,
                    ignoreUnfoundImports: self.ignoreUnfoundImports
                )
                var loopBody = try serializer.serialize(context: innerContext)
                self.buffer.writeBuffer(&loopBody)
            }
        } else {
            throw LeafError(.expectedIterable(got: evalled.concreteType!))
        }
    }
}
