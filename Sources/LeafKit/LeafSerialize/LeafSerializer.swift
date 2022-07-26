import NIO

internal struct LeafSerializer {
    // MARK: - Internal Only
    
    init(
        ast: [Syntax],
        context data: [String: LeafData],
        tags: [String: LeafTag] = defaultTags,
        userInfo: [AnyHashable: Any] = [:],
        ignoreUnfoundImports: Bool
        
    ) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.data = data
        self.tags = tags
        self.userInfo = userInfo
        self.ignoreUnfoundImports = ignoreUnfoundImports
    }
    
    mutating func serialize() throws -> ByteBuffer {
        self.offset = 0
        while let next = self.peek() {
            self.pop()
            try self.serialize(next)
        }
        return self.buffer
    }
    
    // MARK: - Private Only
    
    private let ast: [Syntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private var data: [String: LeafData]
    private let tags: [String: LeafTag]
    private let userInfo: [AnyHashable: Any]
    private let ignoreUnfoundImports: Bool

    private mutating func serialize(_ syntax: Syntax) throws {
        switch syntax {
            case .raw(var byteBuffer): buffer.writeBuffer(&byteBuffer)
            case .custom(let custom):  try serialize(custom)
            case .conditional(let c):  try serialize(c)
            case .loop(let loop):      try serialize(loop)
            case .expression(let exp): try serialize(expression: exp)
            case .import:
                if (self.ignoreUnfoundImports) {
                    break
                } else {
                    fallthrough
                }
            case .extend, .export:
                throw "\(syntax) should have been resolved BEFORE serialization"
        }
    }

    private mutating func serialize(expression: [ParameterDeclaration]) throws {
        let resolved = try self.resolve(parameters: [.expression(expression)])
        guard resolved.count == 1, let leafData = resolved.first else {
            throw "expressions should resolve to single value"
        }
        try? leafData.htmlEscaped().serialize(buffer: &self.buffer)
    }

    private mutating func serialize(body: [Syntax]) throws {
        try body.forEach { try serialize($0) }
    }

    private mutating func serialize(_ conditional: Syntax.Conditional) throws {
        evaluate:
        for block in conditional.chain {
            let evaluated = try resolveAtomic(block.condition.expression())
            guard (evaluated.bool ?? false) || (!evaluated.isNil && evaluated.celf != .bool) else { continue }
            try serialize(body: block.body)
            break evaluate
        }
    }

    private mutating func serialize(_ tag: Syntax.CustomTagDeclaration) throws {
        let sub = try LeafContext(
            parameters: self.resolve(parameters: tag.params),
            data: data,
            body: tag.body,
            userInfo: self.userInfo
        )

        guard let foundTag = self.tags[tag.name] else {
            try? LeafData("#\(tag.name)").serialize(buffer: &self.buffer)
            return
        }

        let leafData: LeafData

        if foundTag is UnsafeUnescapedLeafTag {
            leafData = try foundTag.render(sub)
        } else {
            leafData = try foundTag.render(sub).htmlEscaped()
        }

        try? leafData.serialize(buffer: &self.buffer)
    }


    private mutating func serialize(_ loop: Syntax.Loop) throws {
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

        if let dictionary = finalData[String(pathComponents.last!)]?.dictionary {
            let keys = dictionary.keys.sorted() // make array
            for (idx, key) in keys.enumerated() {
                var innerContext = self.data
                let item = dictionary[key]!

                innerContext["isFirst"] = .bool(idx == keys.startIndex)
                innerContext["isLast"] = .bool(idx == keys.index(before: keys.endIndex))
                innerContext["index"] = .int(idx)
                innerContext["key"] = .string(key)

                innerContext[loop.item] = item

                var serializer = LeafSerializer(
                    ast: loop.body,
                    context: innerContext,
                    tags: self.tags,
                    userInfo: self.userInfo,
                    ignoreUnfoundImports: self.ignoreUnfoundImports
                )
                var loopBody = try serializer.serialize()
                self.buffer.writeBuffer(&loopBody)
            }
        } else if let array = finalData[String(pathComponents.last!)]?.array {
            for (idx, item) in array.enumerated() {
                var innerContext = self.data

                innerContext["isFirst"] = .bool(idx == array.startIndex)
                innerContext["isLast"] = .bool(idx == array.index(before: array.endIndex))
                innerContext["index"] = .int(idx)
                innerContext[loop.item] = item

                var serializer = LeafSerializer(
                    ast: loop.body,
                    context: innerContext,
                    tags: self.tags,
                    userInfo: self.userInfo,
                    ignoreUnfoundImports: self.ignoreUnfoundImports
                )
                var loopBody = try serializer.serialize()
                self.buffer.writeBuffer(&loopBody)
            }
        } else {
            throw "expected array or dictionary at key: \(loop.array)"
        }
    }

    private func resolve(parameters: [ParameterDeclaration]) throws -> [LeafData] {
        let resolver = ParameterResolver(
            params: parameters,
            data: data,
            tags: self.tags,
            userInfo: userInfo
        )
        return try resolver.resolve().map { $0.result }
    }
    
    // Directive resolver for a [ParameterDeclaration] where only one parameter is allowed that must resolve to a single value
    private func resolveAtomic(_ parameters: [ParameterDeclaration]) throws -> LeafData {
        guard parameters.count == 1 else {
            if parameters.isEmpty {
                throw LeafError(.unknownError("Parameter statement can't be empty"))
            } else {
                throw LeafError(.unknownError("Parameter statement must hold a single value"))
            }
        }
        return try resolve(parameters: parameters).first ?? .trueNil
    }

    private func peek() -> Syntax? {
        guard self.offset < self.ast.count else {
            return nil
        }
        return self.ast[self.offset]
    }

    private mutating func pop() { self.offset += 1 }
}
