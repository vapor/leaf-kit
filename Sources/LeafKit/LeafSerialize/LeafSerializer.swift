// MARK: Subject to change prior to 1.0.0 release
// MARK: -
import Foundation

internal struct Leaf4Serializer {
    init(ast: Leaf4AST,
         context: [String: LeafData]) {
        self.ast = ast
        self.stack = []
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LeafConfiguration.timeout
        self.stack.append(.init(count: 1))
        self.stack[0].variables[.`self`] = .dictionary(context)
        expandDict(.dictionary(context))
    }
    
    mutating func expandDict(_ leafData: LeafData, _ base: LeafVariable = .`self`) {
        for (identifier, value) in leafData.dictionary ?? [:] {
            let key: LeafVariable = base.extend(with: identifier)
            stack[depth].variables[key] = value
            if value.celf == .dictionary { expandDict(value, key) }
        }
    }
    
    mutating func serialize(buffer output: UnsafeMutablePointer<RawBlock>,
                            timeout threshold: Double? = nil) -> Result<Double, LeafError> {
        guard !ast.scopes[0].isEmpty else { return .success(0) }
        if let threshold = threshold { self.threshold = threshold }
        self.stack[0].bufferStack.append(output)
        start = Date().timeIntervalSinceReferenceDate
        
        serialize:
        while !stack.isEmpty, !cutoff, error == nil {
            tick()
            
            // At start of a scope block, evaluate the scope. Terminate if it
            // can't evaluate, elide if scope is discard and continue to next
            if currentBlock != nil, table > 0, offset == 0 {
                if currentCount != nil {
                    guard reEvaluateScope() else { continue }
                } else {
                    guard let eval = evaluateScope() else { break }
                    guard eval else { continue }
                }
                
            // Special case for atomic scopes - fully evaluate an "atomic" scope
            // Only passthrough and raw are valid atomic scopes
            } else if currentBlock != nil, table < 0 {
                while currentCount == nil, !cutoff {
                    tick()
                    guard let eval = evaluateScope() else { break serialize }
                    guard eval else { continue serialize }
                    switch ast.scopes[(stack[depth].table * -1) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param):
                            append(param.evaluate(variables))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                }
                while (currentCount ?? 0) > 0, !cutoff {
                    tick()
                    guard reEvaluateScope() else { continue serialize }
                    switch ast.scopes[(stack[depth].table * -1) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param):
                            append(param.evaluate(variables))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                }
                
                offset += 1
                closeScope()
                continue
            }

            let next = peek
            if next == nil && depth == 0 { break }
            switch next?.container {
                // Basic cases. Append evaluated atomics/raws to the current buffer
                case .raw(var raw)           : append(&raw)
                case .passthrough(let param) : append(param.evaluate(variables))
                // Blocks
                case .block(_, let b, let p):
                    // Handle meta first
                    if let meta = b as? MetaBlock {
                        switch meta.form {
                            case .inline:
                                let inline = meta as! Inline
                                newScope(from: inline, params: .init())
                            case .define:
                                /// Push the scope pointer into the current stack's defines and skip next syntax
                                let define = meta as! Define
                                // If define body is nil, unset
                                if case .passthrough(.keyword(.nil)) = scope[offset + 1].container {
                                    stack[depth].defines[define.identifier] = nil
                                }      // .. or add the define to the stack
                                else { stack[depth].defines[define.identifier] = define }
                                offset += 2
                                continue serialize
                            case .evaluate:
                                let evaluate = meta as! Evaluate
                                // If the definition exists, open a new stack and point it at the ref scope or atomic defintion
                                if let jump = stack[depth].defines[evaluate.identifier] {
                                    offset += 2
                                    newScope(from: evaluate, params: .init())
                                    let jumper = ast.scopes[jump.table][jump.row]
                                    if case .scope(let t) = jumper.container {
                                        stack[depth].table = t!
                                    } else {
                                        stack[depth].table = -1 * (jump.table + 1)
                                        stack[depth].offset = jump.row
                                    }
                                    continue serialize
                                 // or if it doesn't....
                                } else if case .scope(nil) = scope[offset + 1].container {
                                    // No defined value; if default value exists instead of nil scope, serialize that
                                    offset += 2; continue serialize
                                    // Or there's a defined value, just skip this scope
                                } else { offset += 1; continue serialize }
                            case .rawSwitch:
                                break // Until raw Blocks are added, non-op - raw stack will always be ByteBuffer
                        }
                    }
                    
                    // Otherwise actual scopes:
                    // Next check if a chained block and not at end of scope.
                    if let chained = b as? ChainedBlock {
                        switch stack[depth].breakChain {
                            // First block in a chain - set state to false
                            case .none        : stack[depth].breakChain = false
                            // Nth block in chain where none succeeded: normal
                            case .some(false) : break
                            // Previous chained block succeeded - elide (and reset breakChain if end)
                            case .some(true)  : offset += 2
                                                if !nextMatchesChain(type(of: chained)) {
                                                    stack[depth].breakChain = nil }
                                                continue serialize
                        }
                    }
                    
                    // Cache the current table/offset for ref if an atomic scope
                    // Signal atomic scopes with -(table + 1) value & the atomic syntax
                    let atomic = (-1 * (table + 1), offset + 1)
                    // Jump over scope block regardless
                    offset += 2
                    
                    // Now handle the following syntax... if scope:
                    if case .scope(let t) = scope[offset + 1].container {
                        if let t = t { // Actual scope reference
                            newScope(from: b, params: p ?? .init(), table: t, offset: 0)
                        }
                        // Nil scope will fall through to `continue serialize`
                    } else { // .... or this is an atomic scope
                        newScope(from: b, params: p ?? .init(), table: atomic.0, offset: atomic.1)
                    }
                   
                    continue serialize
                // Evaluate scope, handle as necessary
                case .scope(_): __MajorBug("Evaluation fail")
                
                // Not in the top level scope and hit the end of the table but not done - repeat
                case .none where currentCount != 0 : offset = 0; continue serialize
                // Done with current scope
                case .none: closeScope()
            }
            offset += 1
        }
        guard !cutoff else { return .failure(LeafError(.unknownError("Execution timed out")))}
        if error == nil { return .success(Date.timeIntervalSinceReferenceDate - start) }
        else { return .failure(error!) }
    }
    
    private let ast: Leaf4AST
    private var error: LeafError? = nil
    
    private struct ScopeState {
        var count: Int? = nil
        var table: Int = 0
        var offset: Int = 0
        var block: LeafBlock? = nil
        var tuple: LeafTuple? = nil
        var breakChain: Bool? = nil
        var variables: SymbolMap = [:]
        var scopeFirstPass: Bool = true
        var scopeIDs: Set<String> = []
        var defines: [String: Define] = [:]
        var bufferStack: [UnsafeMutablePointer<RawBlock>] = []
        
        init(count: Int? = nil) { self.count = count }
        
        init(from: Self, block: LeafBlock, tuple: LeafTuple) {
            self.block = block
            self.tuple = tuple
            self.variables = from.variables
            self.defines = from.defines
            self.bufferStack = from.bufferStack
        }
    }
    
    private var stack: [ScopeState]
    
    private var depth: Int { stack.count - 1 }
    private var table: Int { stack[depth].table }
    private var scope: [Leaf4Syntax] { ast.scopes[table] }
    private var evalCount: Int? { stack[depth].count }
    private var variables: SymbolMap { stack[depth].variables }
    private var currentRaw: Int { stack[depth].bufferStack.count - 1 }
    private var currentCount: Int? { stack[depth].count }
    private var currentBlock: LeafBlock? { stack[depth].block }
  
    private var offset: Int {
        get { stack[depth].offset }
        set { stack[depth].offset = newValue }
    }
    
    private var idCache: [String: LeafVariable] = [:]
    
    private var peek: Leaf4Syntax? { scope.count > offset ? scope[offset] : nil }
    
    private mutating func newScope(from block: LeafBlock,
                                   params tuple: LeafTuple,
                                   table: Int,
                                   offset: Int) {
        stack.append(.init(from: stack[depth], block: block, tuple: tuple))
        stack[depth].table = table
        stack[depth].offset = offset
    }
    
    private mutating func closeScope() {
        precondition(stack.count > 1, "Can't close top scope")
        // Store the current block type if it's chained before closing current scope
        let chained = currentBlock as? ChainedBlock
        stack.removeLast()
        // Reset breakChain if we were at end of chain
        if let chained = chained, !nextMatchesChain(type(of: chained)) {
            stack[depth].breakChain = nil
        }
    }
    
    private func nextMatchesChain(_ antecedent: ChainedBlock.Type) -> Bool {
        guard stack[depth].breakChain != nil, let next = peek,
              case .block(_, let n as ChainedBlock, _) = next.container,
              type(of: n).chainsTo.contains(where: {$0 == antecedent}) else { return false }
        return true
    }
    
    private var start: Double
    private var lapTime: Double
    private var threshold: Double
    private var tickCount: UInt8 = 0
    private var cutoff: Bool { threshold < (lapTime - start) }
    
    mutating private func tick() { tickCount &+= 1; if tickCount == 0 { lap() } }
    mutating private func lap() { lapTime = Date().timeIntervalSinceReferenceDate }
    
    
    mutating func evaluateScope() -> Bool? {
        if table < 0 || (table > 0 && offset == 0), stack[depth].block != nil {
            guard let params = ParameterValues(stack[depth].block!.sig, stack[depth].tuple!, variables) else {
                error = LeafError(.unknownError("Couldn't evaluate scope variables"))
                return nil
            }
            var scopeVariables: [String: LeafData] = [:]
            let scopeValue = stack[depth].block!.evaluateNilScope(params, &scopeVariables)
            // if evaluate to discard, stop immediately and end the current block
            if scopeValue == 0 { closeScope(); return false }
            
            // If this is a chained block, we've hit - set breakChain at the previous stack depth
            if currentBlock as? ChainedBlock != nil { stack[depth - 1].breakChain = true }
            
            if !scopeVariables.isEmpty {
                for (key, value) in scopeVariables where key.isValidIdentifier {
                    stack[depth].scopeIDs.insert(key)
                    idCache[key] = .atomic(key)
                    stack[depth].variables[idCache[key]!] = value
                    if value.celf == .dictionary { expandDict(value, idCache[key]!) }
                }
            }
            if let count = scopeValue { stack[depth].count = count - 1 }
            else { stack[depth].count = nil }
        }
        return true
    }
    
    mutating func reEvaluateScope() -> Bool {
        if stack[depth].block != nil, currentCount != nil, currentCount! > 0 {
            var scopeVariables: [String: LeafData] = [:]
            let scopeValue = stack[depth].block!.reEvaluateScope(&scopeVariables)
            // if evaluate to discard, stop immediately and end the current block
            guard let toGo = scopeValue else {
                error = LeafError(.unknownError("Blocks must not return nil evaluation after having reported a concrete count"))
                return false
            }
            if toGo == 0 { closeScope(); return false }
            for (key, value) in scopeVariables where stack[depth].scopeIDs.contains(key) {
                stack[depth].variables[idCache[key]!] = value
                if value.celf == .dictionary { expandDict(value, idCache[key]!) }
            }
            stack[depth].count = toGo - 1
            return true
        } else { return false }
    }
}

extension Leaf4Serializer {
    mutating func append(_ block: inout RawBlock) {
        do { try stack[depth].bufferStack[currentRaw].pointee.append(&block) }
        catch { self.error = LeafError(.unknownError("Serializing error")) }
    }
    
    mutating func append(_ buffer: inout ByteBuffer) {
        do { try stack[depth].bufferStack[currentRaw].pointee.append(&buffer) }
        catch { self.error = LeafError(.unknownError("Serializing error")) }
    }
    
    mutating func append(_ data: LeafData) {
        stack[depth].bufferStack[currentRaw].pointee.append(data)
    }
}



internal struct LeafSerializer {
    // MARK: - Internal Only
    
    init(
        ast: [Syntax],
        context data: [String: LeafData],
        tags: [String: LeafTag] = defaultTags,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.ast = ast
        self.offset = 0
        self.buffer = ByteBufferAllocator().buffer(capacity: ast.count * 16)
        self.data = data
        self.tags = tags
        self.userInfo = userInfo
    }
    
    mutating func serialize() throws -> ByteBuffer {
        offset = 0
        while let next = peek { pop(); try serialize(next) }
        return buffer
    }
    
    // MARK: - Private Only
    
    private let ast: [Syntax]
    private var offset: Int
    private var buffer: ByteBuffer
    private var data: [String: LeafData]
    private let tags: [String: LeafTag]
    private let userInfo: [AnyHashable: Any]

    private mutating func serialize(_ syntax: Syntax) throws {
        switch syntax {
            case .raw(var byteBuffer): buffer.writeBuffer(&byteBuffer)
            case .custom(let custom):  try serialize(custom)
            case .conditional(let c):  try serialize(c)
            case .loop(let loop):      try serialize(loop)
            case .expression(let exp): try serialize(expression: exp)
            case .import, .extend, .export:
                throw "\(syntax) should have been resolved BEFORE serialization"
        }
    }

    private mutating func serialize(expression: [ParameterDeclaration]) throws {
        let resolved = try self.resolve(parameters: [.expression(expression)])
        guard resolved.count == 1, let leafData = resolved.first else {
            throw "expressions should resolve to single value"
        }
        try? leafData.serialize(buffer: &self.buffer)
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
        let sub = try LeafContext(resolve(parameters: tag.params),
                                  data, tag.body, userInfo)
        let leafData = try self.tags[tag.name]?.render(sub) ?? LeafData.trueNil
        try? leafData.serialize(buffer: &self.buffer)
    }
    
    private mutating func serialize(_ loop: Syntax.Loop) throws {
        let finalData: [String: LeafData]
        var pathComponents = loop.array.split(separator: ".")
        pathComponents = pathComponents.filter { !$0.hasPrefix("$") }
        
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
        } else { finalData = data }

        guard let array = finalData[String(pathComponents.last!)]?.array else {
            throw "expected array at key: \(loop.array)"
        }

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
                userInfo: self.userInfo
            )
            var loopBody = try serializer.serialize()
            self.buffer.writeBuffer(&loopBody)
        }
    }

    private func resolve(parameters: [ParameterDeclaration]) throws -> [LeafData] {
        let resolver = ParameterResolver(parameters, data, tags, userInfo)
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

    private var peek: Syntax? { offset < ast.count ? ast[offset] : nil }

    private mutating func pop() { offset += 1 }
}
