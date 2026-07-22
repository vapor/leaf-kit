import NIOCore

struct LeafSerializer {
    // MARK: - Internal Only

    init(
        ast: [Syntax],
        tags: [String: any LeafTag] = defaultTags,
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
        self.offset = 0
        while let next = self.peek() {
            self.pop()
            try self.serialize(next, context: data)
        }
        return self.buffer
    }

    // MARK: - Private Only

    private let ast: [Syntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private let tags: [String: any LeafTag]
    private let userInfo: [AnyHashable: Any]
    private let ignoreUnfoundImports: Bool

    private mutating func serialize(_ syntax: Syntax, context data: [String: LeafData]) throws {
        switch syntax {
        case .raw(var byteBuffer): self.buffer.writeBuffer(&byteBuffer)
        case .custom(let custom): try self.serialize(custom, context: data)
        case .conditional(let c): try self.serialize(c, context: data)
        case .loop(let loop): try self.serialize(loop, context: data)
        case .with(let with): try self.serialize(with, context: data)
        case .expression(let exp): try self.serialize(expression: exp, context: data)
        case .import:
            if self.ignoreUnfoundImports {
                break
            } else {
                fallthrough
            }
        case .extend, .export:
            throw LeafError.unknownError("\(syntax) should have been resolved BEFORE serialization")
        }
    }

    private mutating func serialize(expression: [ParameterDeclaration], context data: [String: LeafData]) throws {
        let resolved = try self.resolve(parameters: [.expression(expression)], context: data)
        guard resolved.count == 1, let leafData = resolved.first else {
            throw LeafError.unknownError("expressions should resolve to single value")
        }
        try? leafData.htmlEscaped().serialize(buffer: &self.buffer)
    }

    private mutating func serialize(body: [Syntax], context data: [String: LeafData]) throws {
        try body.forEach { try self.serialize($0, context: data) }
    }

    private mutating func serialize(_ conditional: Syntax.Conditional, context data: [String: LeafData]) throws {
        evaluate: for block in conditional.chain {
            let evaluated = try self.resolveAtomic(block.condition.expression(), context: data)
            guard (evaluated.bool ?? false) || (!evaluated.isNil && evaluated.celf != .bool) else {
                continue
            }
            try self.serialize(body: block.body, context: data)
            break evaluate
        }
    }

    private mutating func serialize(_ tag: Syntax.CustomTagDeclaration, context data: [String: LeafData]) throws {
        let sub = try LeafContext(
            parameters: self.resolve(parameters: tag.params, context: data),
            data: data,
            body: tag.body,
            userInfo: self.userInfo
        )

        guard let foundTag = self.tags[tag.name] else {
            try? LeafData("#\(tag.name)").serialize(buffer: &self.buffer)
            return
        }

        let leafData: LeafData

        if foundTag is any UnsafeUnescapedLeafTag {
            leafData = try foundTag.render(sub)
        } else {
            leafData = try foundTag.render(sub).htmlEscaped()
        }

        try? leafData.serialize(buffer: &self.buffer)
    }

    private mutating func serialize(_ with: Syntax.With, context data: [String: LeafData]) throws {
        let resolved = try self.resolve(parameters: [.expression(with.context)], context: data)
        guard resolved.count == 1,
            let dict = resolved[0].dictionary
        else {
            throw LeafError.unknownError("expressions should resolve to a single dictionary value")
        }

        try? self.serialize(body: with.body, context: dict)
    }

    private mutating func serialize(_ loop: Syntax.Loop, context data: [String: LeafData]) throws {
        let finalData: [String: LeafData]
        let pathComponents = loop.array.split(separator: ".")

        if pathComponents.count > 1 {
            finalData = try pathComponents[0..<(pathComponents.count - 1)].enumerated()
                .reduce(data) { (innerData, pathContext) -> [String: LeafData] in
                    let key = String(pathContext.element)

                    guard let nextData = innerData[key]?.dictionary else {
                        let currentPath = pathComponents[0...pathContext.offset].joined(separator: ".")
                        throw LeafError.unknownError("expected dictionary at key: \(currentPath)")
                    }

                    return nextData
                }
        } else {
            finalData = data
        }

        guard let array = finalData[String(pathComponents.last!)]?.array else {
            throw LeafError.unknownError("expected array at key: \(loop.array)")
        }

        for (idx, item) in array.enumerated() {
            var innerContext = data

            innerContext["isFirst"] = .bool(idx == array.startIndex)
            innerContext["isLast"] = .bool(idx == array.index(before: array.endIndex))
            innerContext[loop.index] = .int(idx)
            innerContext[loop.item] = item

            var serializer = LeafSerializer(
                ast: loop.body,
                tags: self.tags,
                userInfo: self.userInfo,
                ignoreUnfoundImports: self.ignoreUnfoundImports
            )
            var loopBody = try serializer.serialize(context: innerContext)
            self.buffer.writeBuffer(&loopBody)
        }
    }

    private func resolve(parameters: [ParameterDeclaration], context data: [String: LeafData]) throws -> [LeafData] {
        let resolver = ParameterResolver(
            params: parameters,
            data: data,
            tags: self.tags,
            userInfo: self.userInfo
        )
        return try resolver.resolve().map { $0.result }
    }

    // Directive resolver for a [ParameterDeclaration] where only one parameter is allowed that must resolve to a single value
    private func resolveAtomic(_ parameters: [ParameterDeclaration], context data: [String: LeafData]) throws -> LeafData {
        guard parameters.count == 1 else {
            if parameters.isEmpty {
                throw LeafError.unknownError("Parameter statement can't be empty")
            } else {
                throw LeafError.unknownError("Parameter statement must hold a single value")
            }
        }
        return try self.resolve(parameters: parameters, context: data).first ?? .trueNil
    }

    private func peek() -> Syntax? {
        guard self.offset < self.ast.count else {
            return nil
        }
        return self.ast[self.offset]
    }

    private mutating func pop() {
        self.offset += 1
    }
}
