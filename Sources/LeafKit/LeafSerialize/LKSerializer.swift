// MARK: Subject to change prior to 1.0.0 release
// MARK: -
import Foundation

internal final class LKSerializer {
    private var stack: ContiguousArray<ScopeState>
    private var stackDepth: Int = 0
    
    private var context: UnsafeMutablePointer<LKVarTable>
    
    private var currentState: ScopeState { stack[stackDepth] }
    
    private var table: Int { currentState.table }
    private var scope: ContiguousArray<LKSyntax> { ast.scopes[table] }
    private var evalCount: Int? { currentState.count }
    private var currentVariables: UnsafeMutablePointer<LKVarTable> { currentState.variables.0 }
    private var currentRaw: Int { currentState.bufferStack.count - 1 }
    private var currentCount: Int? { currentState.count }
    private var currentBlock: LeafBlock? { currentState.block }
    private var currentTuple: LKTuple? { currentState.tuple }
  
    private var offset: Int {
        get { stack[stackDepth].offset }
        set { stack[stackDepth].offset = newValue }
    }
    
    private var idCache: [String: LKVariable] = [:]
    
    private var peek: LKSyntax? { scope.count > offset ? scope[offset] : nil }
    
    init(ast: LeafAST, context: [String: LKD]) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LKConf.timeout
        self.context = UnsafeMutablePointer<LKVarTable>.allocate(capacity: 1)
        self.context.initialize(to: .init(minimumCapacity: context.count * 2))
        self.context.pointee[.`self`] = .dictionary(context)
        self.stack = .init(repeating: .init(count: 1,
                                            variables: self.context),
                           count: Int(ast.info.stackDepths.overallMax))
        expandDict(.dictionary(context), .`self`, false)
    }
    
    deinit { self.context.deallocate() }
    
    func expandDict(_ data: LKD, _ base: LKVariable = .`self`, _ toStack: Bool = true) {
        data.dictionary.map {
            for (identifier, value) in $0 {
                let key: LKVariable = base.extend(with: identifier)
                if toStack { currentVariables.pointee[key] = value }
                else { context.pointee[key] = value }
                if value.celf == .dictionary { expandDict(value, key, toStack) }
            }
        }
    }
    
    func serialize(buffer output: inout RawBlock,
                   timeout threshold: Double? = nil) -> Result<Double, LeafError> {
        guard !ast.scopes[0].isEmpty else { return .success(0) }
        if let threshold = threshold { self.threshold = threshold }
        
        let ptr = UnsafeMutablePointer<RawBlock>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        ptr.initialize(to: type(of: output).instantiate(size: ast.info.averages.size,
                                                        encoding: LKConf.encoding))
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
                    switch ast.scopes[(currentState.table * -1) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param):
                            append(param.evaluate(currentVariables.pointee))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                }
                while (currentCount ?? 0) > 0, !cutoff {
                    tick()
                    guard reEvaluateScope() else { continue serialize }
                    switch ast.scopes[(currentState.table * -1) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param):
                            append(param.evaluate(currentVariables.pointee))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                }
                
                offset += 1
                closeScope()
                continue
            }

            let next = peek
            if next == nil && stackDepth == 0 { break }
            switch next?.container {
                // Basic cases. Append evaluated atomics/raws to the current buffer
                case .raw(var raw)           : append(&raw)
                case .passthrough(let param) : append(param.evaluate(currentVariables.pointee))
                // Blocks
                case .block(_, let b, let p):
                    // Handle meta first
                    if let meta = b as? LKMetaBlock {
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
                                    stack[stackDepth].defines[define.identifier] = nil
                                }      // .. or add the define to the stack
                                else { stack[stackDepth].defines[define.identifier] = define }
                                offset += 2
                                continue serialize
                            case .evaluate:
                                let evaluate = meta as! Evaluate
                                // If the definition exists, open a new stack and point it at the ref scope or atomic defintion
                                if let jump = currentState.defines[evaluate.identifier] {
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
                        switch currentState.breakChain {
                            // First block in a chain - set state to false
                            case .none        : stack[stackDepth].breakChain = false
                            // Nth block in chain where none succeeded: normal
                            case .some(false) : break
                            // Previous chained block succeeded - elide (and reset breakChain if end)
                            case .some(true)  : offset += 2
                                                if !nextMatchesChain(type(of: chained)) {
                                                    stack[stackDepth].breakChain = nil }
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
    
    private let ast: LeafAST
    private var error: LeafError? = nil
    
    private struct ScopeState {
        var count: Int? = nil
        var table: Int = 0
        var offset: Int = 0
        var block: LeafBlock? = nil
        var tuple: LKTuple? = nil
        var breakChain: Bool? = nil
        var variables: (UnsafeMutablePointer<LKVarTable>, allocated: Bool)
        var scopeFirstPass: Bool = true
        var scopeIDs: Set<String> = []
        var defines: [String: Define] = [:]
        var bufferStack: [UnsafeMutablePointer<RawBlock>] = []
        
        init(count: Int? = nil, variables: UnsafeMutablePointer<LKVarTable>) {
            self.count = count
            self.variables = (variables, false)
        }
        
        init(from: Self, block: LeafBlock, tuple: LKTuple) {
            self.block = block
            self.tuple = tuple
            self.variables = (from.variables.0, false)
            self.defines = from.defines
            self.bufferStack = from.bufferStack
        }
    }
    
    func newScope(from block: LeafBlock,
                                   params tuple: LKTuple,
                                   table: Int,
                                   offset: Int) {
        let new: ScopeState = .init(from: stack[stackDepth], block: block, tuple: tuple)
        stackDepth += 1
        if stackDepth == stack.count { stack.append(new) }
        else { stack[stackDepth] = new }
        stack[stackDepth].table = table
        stack[stackDepth].offset = offset
        block.scopeVariables.map {
            for identifier in $0 where identifier.isValidIdentifier {
                idCache[identifier] = .atomic(identifier)
                stack[stackDepth].scopeIDs.insert(identifier)
            }
        }
    }
    
    func closeScope() {
        precondition(stack.count > 1, "Can't close top scope")
        if currentState.variables.allocated { currentState.variables.0.deallocate() }
        stackDepth -= 1
        // Reset breakChain if we were at end of chain
        if let chained = stack[stackDepth + 1].block as? ChainedBlock,
           !nextMatchesChain(type(of: chained)) {
            stack[stackDepth].breakChain = nil
        }
    }
    
    private func nextMatchesChain(_ antecedent: ChainedBlock.Type) -> Bool {
        guard stack[stackDepth].breakChain != nil, let next = peek,
              case .block(_, let n as ChainedBlock, _) = next.container,
              type(of: n).chainsTo.contains(where: {$0 == antecedent}) else { return false }
        return true
    }
    
    private var start: Double
    private var lapTime: Double
    private var threshold: Double
    private var tickCount: UInt8 = 0
    private var cutoff: Bool { threshold < (lapTime - start) }
    
    private func tick() { tickCount &+= 1; if tickCount == 0 { lap() } }
    private func lap() { lapTime = Date().timeIntervalSinceReferenceDate }
    
    func evaluateScope() -> Bool? {
        if table < 0 || (table > 0 && offset == 0), currentBlock != nil {
            // All metablocks will always run only once
            guard currentBlock as? LKMetaBlock == nil else { stack[stackDepth].count = 0
                                                           return true }
            
            guard let params = ParameterValues(currentBlock!.sig, currentTuple!, currentVariables.pointee) else {
                error = LeafError(.unknownError("Couldn't evaluate scope parameters"))
                return nil
            }
            var scopeVariables: [String: LeafData] = .init(uniqueKeysWithValues: currentState.scopeIDs.map { ($0, .trueNil) })
            let scopeValue = stack[stackDepth].block!.evaluateNilScope(params, &scopeVariables)
            // if evaluate to discard, stop immediately and end the current block
            if scopeValue == 0 { closeScope(); return false }
            
            // If this is a chained block, we've hit - set breakChain at the previous stack depth
            if currentBlock as? ChainedBlock != nil { stack[stackDepth - 1].breakChain = true }
            
            if !scopeVariables.isEmpty {
                let newVars = UnsafeMutablePointer<LKVarTable>.allocate(capacity: 1)
                newVars.initialize(from: stack[stackDepth].variables.0, count: 1)
                stack[stackDepth].variables = (newVars, true)
                for (key, value) in scopeVariables where currentState.scopeIDs.contains(key) {
                    currentVariables.pointee[idCache[key]!] = value
                    if value.celf == .dictionary { expandDict(value, idCache[key]!) }
                }
            }
            if let count = scopeValue { stack[stackDepth].count = count - 1 }
            else { stack[stackDepth].count = nil }
        }
        return true
    }
    
    func reEvaluateScope() -> Bool {
        if currentBlock != nil, currentCount != nil, currentCount! > 0 {
            var scopeVariables: [String: LeafData] = .init(uniqueKeysWithValues: currentState.scopeIDs.map { ($0, .trueNil) })
            let scopeValue = stack[stackDepth].block!.reEvaluateScope(&scopeVariables)
            // if evaluate to discard, stop immediately and end the current block
            guard let toGo = scopeValue else {
                error = LeafError(.unknownError("Blocks must not return nil evaluation after having reported a concrete count"))
                return false
            }
            if toGo == 0 { closeScope(); return false }
            for (key, value) in scopeVariables where stack[stackDepth].scopeIDs.contains(key) {
                currentVariables.pointee[idCache[key]!] = value
                if value.celf == .dictionary { expandDict(value, idCache[key]!) }
            }
            stack[stackDepth].count = toGo - 1
            return true
        } else { return false }
    }
    
    @inline(__always)
    func append(_ block: inout RawBlock) {
        do { try stack[stackDepth].bufferStack[currentRaw].pointee.append(&block) }
        catch { self.error = LeafError(.unknownError("Serializing error")) }
    }
  
    @inline(__always)
    func append(_ data: LeafData) {
        stack[stackDepth].bufferStack[currentRaw].pointee.append(data)
    }
}
