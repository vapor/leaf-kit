// MARK: Subject to change prior to 1.0.0 release
// MARK: -
import Foundation

internal struct Leaf4Serializer {
    init(ast: Leaf4AST,
         context: [String: LeafData]) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LeafConfiguration.timeout
        self.stack = .init()
        self.stack.reserveCapacity(16)
        self.stack.append(.init(count: 1,
                                variables: .init(minimumCapacity: 64)))
        self.stack[0].variables[.`self`] = .dictionary(context)
        expandDict(.dictionary(context))
    }
    
    mutating func expandDict(_ leafData: LeafData, _ base: LKVariable = .`self`) {
        for (identifier, value) in leafData.dictionary ?? [:] {
            let key: LKVariable = base.extend(with: identifier)
            stack[depth].variables[key] = value
            if value.celf == .dictionary { expandDict(value, key) }
        }
    }
    
    mutating func serialize(buffer output: inout RawBlock,
                            timeout threshold: Double? = nil) -> Result<Double, LeafError> {
        guard !ast.scopes[0].isEmpty else { return .success(0) }
        if let threshold = threshold { self.threshold = threshold }
        
        let ptr = UnsafeMutablePointer<RawBlock>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        ptr.initialize(to: type(of: output).instantiate(size: ast.info.averages.size,
                                                        encoding: LeafConfiguration.encoding))
        self.stack[0].bufferStack.append(ptr)
        
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
                            case .inline: // Elide - scope block dictates action
                                break
//                                let inline = meta as! Inline
//                                newScope(from: inline, params: .init(), table: , offset: )
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
                                    let jumper = ast.scopes[jump.table][jump.row]
                                    if case .scope(let t) = jumper.container {
                                        if let t = t {
                                            newScope(from: evaluate, params: .init(), table: t, offset: 0)
                                        }
                                    } else {
                                        newScope(from: evaluate, params: .init(), table: -1 * (jump.table + 1), offset: jump.row)
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
                    let syntax = scope[offset + 1].container
                    // Jump over scope block regardless
                    offset += 2
                    
                    // Now handle the following syntax... if scope:
                    if case .scope(let t) = syntax {
                        if let t = t { // Actual scope reference
                            newScope(from: b, params: p ?? .init(), table: t, offset: 0)
                        }
                        // Nil scope will fall through to `continue serialize`
                    } else { // .... or this is an atomic scope
                        newScope(from: b, params: p ?? .init(), table: atomic.0, offset: atomic.1)
                    }
                   
                    continue serialize
                // Evaluate scope, handle as necessary
                case .scope(_): __MajorBug("Evaluation fail - should never hit scope")
                
                // Not in the top level scope and hit the end of the table but not done - repeat
                case .none where currentCount != 0 : offset = 0; continue serialize
                // Done with current scope
                case .none: closeScope(); continue serialize
            }
            offset += 1
        }
        stack.removeAll()
        output = ptr.pointee
        
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
        
        init(count: Int? = nil, variables: SymbolMap = [:]) {
            self.count = count
            self.variables = variables
        }
        
        init(from: Self, block: LeafBlock, tuple: LeafTuple) {
            self.block = block
            self.tuple = tuple
            self.variables = from.variables
            self.defines = from.defines
            self.bufferStack = from.bufferStack
        }
    }
    
    private var stack: ContiguousArray<ScopeState>
    
    private var depth: Int { stack.count - 1 }
    private var table: Int { stack[depth].table }
    private var scope: ContiguousArray<Leaf4Syntax> { ast.scopes[table] }
    private var evalCount: Int? { stack[depth].count }
    private var variables: SymbolMap { stack[depth].variables }
    private var currentRaw: Int { stack[depth].bufferStack.count - 1 }
    private var currentCount: Int? { stack[depth].count }
    private var currentBlock: LeafBlock? { stack[depth].block }
  
    private var offset: Int {
        get { stack[depth].offset }
        set { stack[depth].offset = newValue }
    }
    
    private var idCache: [String: LKVariable] = [:]
    
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
            // All metablocks will always run only once
            guard stack[depth].block as? MetaBlock == nil else { stack[depth].count = 0
                                                                 return true }
            
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
    
    @inline(__always)
    mutating func append(_ block: inout RawBlock) {
        do { try stack[depth].bufferStack[currentRaw].pointee.append(&block) }
        catch { self.error = LeafError(.unknownError("Serializing error")) }
    }
    
    @inline(__always)
    mutating func append(_ buffer: inout ByteBuffer) {
        do { try stack[depth].bufferStack[currentRaw].pointee.append(&buffer) }
        catch { self.error = LeafError(.unknownError("Serializing error")) }
    }
    
    @inline(__always)
    mutating func append(_ data: LeafData) {
        stack[depth].bufferStack[currentRaw].pointee.append(data)
    }
}
