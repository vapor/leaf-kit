// MARK: Subject to change prior to 1.0.0 release
// MARK: -
import Foundation

internal final class LKSerializer: LKErroring {
    
    // MARK: Stored Properties
    let ast: LeafAST
    internal private(set) var error: LeafError? = nil
        
    private var threshold: Double
    private var start: Double
    private var lapTime: Double
    private var duration: Double = 0
    private var tickCount: UInt8 = 0
    
    private var idCache: [String: LKVariable] = [:]
    
    private var stack: ContiguousArray<ScopeState> = []
    private var stackDepth: Int = 0
    
    private var varStack: LKVarStack = []
    private var varStackDepth: Int = 0
    
    private var bufferStack: [UnsafeMutablePointer<LKRawBlock>] = []
    private var bufferStackDepth: Int = 0
    
    
    // MARK: Computed Properties
    /// Note - these are conveniences - most explicitly do not have setters to avoid overhead of get/set copying
    private var table: Int { stack[stackDepth].table }
    private var scope: ContiguousArray<LKSyntax> { ast.scopes[table] }
    private var defines: [String: Define] { stack[stackDepth].defines }
    private var breakChain: Bool? { get { stack[stackDepth].breakChain } set { stack[stackDepth].breakChain = newValue } }
    private var scopeIDs: Set<String> { varStack[varStackDepth].ids }
    private var vars: LKVarTablePtr { varStack[varStackDepth].vars }
    private var unsafe: ExternalObjects? { varStack[0].unsafe }
    private var allocated: Bool { get { stack[stackDepth].allocated } set { stack[stackDepth].allocated = newValue} }
    private var count: UInt32? { get {stack[stackDepth].count} set { stack[stackDepth].count = newValue } }
    private var block: LeafBlock? { stack[stackDepth].block }
    private var tuple: LKTuple? { stack[stackDepth].tuple }
    private var buffer: UnsafeMutablePointer<LKRawBlock> { bufferStack[bufferStackDepth] }

    private var offset: Int { stack[stackDepth].offset }
    private func advance(by offset: Int = 1) { stack[stackDepth].offset += offset }
    
    @inline(__always)
    private var cutoff: Bool {
        tickCount &+= 1
        if tickCount == 0 { lap() }
        if threshold < (lapTime - start) {
            duration += lapTime - start
            error = err(.timeout(duration))
        }
        return errored
    }
    
    private var peek: LKSyntax? { scope.count > offset ? scope[offset] : nil }

    init(_ ast: LeafAST, _ context: [String: LKData], _ output: LKRawBlock.Type) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LKConf.timeout
        self.varStack.reserveCapacity(Int(ast.info.stackDepths.overallMax))
        self.varStack.append(([], LKVarTablePtr.allocate(capacity: 1), nil))
        self.bufferStack.append(UnsafeMutablePointer<LKRawBlock>.allocate(capacity: 1))
        self.bufferStack[0].initialize(to: output.instantiate(size: ast.info.touch.sizeAvg,
                                                              encoding: LKConf.encoding))
        self.stack = .init(repeating: .init(bufferStack[0]),
                           count: Int(ast.info.stackDepths.overallMax))
        
        vars.initialize(to: .init(minimumCapacity: context.count * 2))
        vars.pointee[.`self`] = .dictionary(context)
        expandDict(.dictionary(context), .`self`)
    }
    
    init(_ ast: LeafAST, varTable: LKVarTable, _ output: LKRawBlock.Type, _ userInfo: ExternalObjects? = nil) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LKConf.timeout
        self.varStack.reserveCapacity(Int(ast.info.stackDepths.overallMax))
        self.varStack.append(([], LKVarTablePtr.allocate(capacity: 1), nil))
        self.bufferStack.append(UnsafeMutablePointer<LKRawBlock>.allocate(capacity: 1))
        self.bufferStack[0].initialize(to: output.instantiate(size: ast.info.touch.sizeAvg,
                                                              encoding: LKConf.encoding))
        self.stack = .init(repeating: .init(bufferStack[0]),
                           count: Int(ast.info.stackDepths.overallMax))
        vars.initialize(to: .init(minimumCapacity: varTable.count * 2))
        vars.pointee = varTable
        for (key, value) in vars.pointee where value.celf == .dictionary {
            expandDict(value, key) }
    }

    deinit {
        while !varStack.isEmpty {
            vars.deinitialize(count: 1)
            vars.deallocate()
            varStack.removeLast()
        }
        bufferStack[0].deinitialize(count: 1)
        bufferStack[0].deallocate()
    }

    private func expandDict(_ data: LKData,
                            _ base: LKVariable = .`self`,
                            at level: Int? = nil) {
        var recurse: [(LKVariable, LKData)] = []
        let level = level ?? varStackDepth
        data.dictionary.map {
            for (identifier, value) in $0 {
                let key: LKVariable = base.extend(with: identifier)
                varStack[level].vars.pointee[key] = value
                if value.celf == .dictionary { recurse.append((key, value)) }
            }
        }
        while let x = recurse.popLast() { expandDict(x.1, x.0, at: level) }
    }

    func serialize(_ output: inout LKRawBlock,
                   _ timeout: Double? = nil,
                   _ resume: Bool = false) -> Result<Double, LeafError> {
        if resume { error = nil }
        guard !ast.scopes[0].isEmpty else { return .success(0) }
        if let timeout = timeout { threshold = timeout }
        start = Date.timeIntervalSinceReferenceDate
        lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        serialize:
        while !cutoff, !errored, !stack.isEmpty {
            /// At start of a scope block, evaluate the scope. Terminate if it
            /// can't evaluate, elide if scope is discard and continue to next
            if table > 0, offset == 0 {
                if count ?? 0 > 0 { guard reEvaluateScope() else { continue } }
                else {
                    guard let run = block != nil ? evaluateScope() : true else { break }
                    guard run else { continue }
                }
            /// Special case for atomic scopes - fully evaluate an "atomic" scope
            /// Only passthrough and raw are valid atomic scopes
            } else if table < 0 {
                /// Run repeated nils
                while count == nil {
                    guard let run = block != nil ? evaluateScope() : true else { break serialize }
                    guard run else { continue serialize }
                    switch ast.scopes[(table * -1) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param): append(param.evaluate(varStack))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                    if cutoff { break serialize }
                }
                /// Run non-nils
                while count! > 0, !cutoff {
                    guard reEvaluateScope() else { continue serialize }
                    switch ast.scopes[(-1 * table) - 1][offset].container {
                        case .raw(var raw): append(&raw)
                        case .passthrough(let param): append(param.evaluate(varStack))
                        default: __MajorBug("Non-atomic atomic scope")
                    }
                }

                advance()
                closeScope()
                continue
            }

            let next = peek
            if next == nil && stackDepth == 0 { break }
            switch next?.container {
                // Basic cases. Append evaluated atomics/raws to the current buffer
                case .raw(var raw)           : append(&raw)
                case .passthrough(let param) :
                    if case .expression(let exp) = param {
                        if exp.form.exp == .assignment {
                            let result = exp.evalAssignment(varStack)
                            switch result {
                                case .success(let val): assignValue(val.0, val.1)
                                case .failure(let err): return .failure(err)
                            }
                        } else if let x = exp.declaresVariable {
                            if !allocated {
                                allocated = true
                                varStackDepth += 1
                                varStack.append(([], .allocate(capacity: 1), nil))
                                vars.initialize(to: .init())
                                vars.pointee[x.variable] = .trueNil
                            }
                            assignValue(x.variable, x.set?.evaluate(varStack) ?? .trueNil)
                        } else { append(param.evaluate(varStack)) }
                        break
                    }
                    
                    append(param.evaluate(varStack))
                // Blocks
                case .block(_, let b, let p):
                    /// Handle meta first
                    if let meta = b as? LKMetaBlock {
                        switch meta.form {
                            case .inline    : break /// Elide - scope block dictates action
                            case .rawSwitch : break /// Until raw Blocks are added, non-op - raw stack will always be ByteBuffer
                            case .define    :
                                /// Push the scope pointer into the current stack's defines and skip next syntax
                                let define = meta as! Define
                                let id = define.identifier
                                let set: Bool
                                /// If define body is nil, unset if defines exists
                                if case .keyword(.nil) = define.param?.container
                                { set = false } else { set = true }
                                stack[stackDepth].defines[id] = set ? define : nil
                                /// If define is param-evaluable, push identifier into variable stack with a lazy calculator
                                if let param = define.param {
                                    if !allocated {
                                        allocated = true
                                        varStackDepth += 1
                                        varStack.append(([], .allocate(capacity: 1), nil))
                                        vars.initialize(to: .init())
                                    }
                                    vars.pointee[.define(id)] = set ? .init(.evaluate(param: param.container)) : nil
                                }
                                advance(by: 2)
                                continue serialize
                            case .evaluate :
                                let evaluate = meta as! Evaluate
                                advance(by: 2)
                                /// If the definition exists, open a new stack and point it at the ref scope or atomic defintion
                                if let jump = defines[evaluate.identifier] {
                                    let land = ast.scopes[jump.table][jump.row]
                                    let t = land.table * (land.table > 0 ? 1 : jump.table + 1)
                                    let o = t > 0 ? 0 : jump.row
                                    if t != 0 { newScope(from: evaluate, p: nil, t: t, o: o) }
                                /// or if no definition but evaluate has a default value roll back one and serialize that
                                } else if evaluate.defaultValue != nil { advance(by: -1) }
                                continue serialize
                        }
                    }
                    /// Otherwise actual scopes: Next check if a chained block and not at end of scope.
                    if let chained = b as? ChainedBlock {
                        if breakChain == true {
                            advance(by: 2)
                            if !nextMatchesChain(type(of: chained)) { breakChain = nil }
                            continue serialize
                        } else if breakChain == nil { breakChain = false }
                    }
                    
                    /// Cache the current table/offset for ref if an atomic scope
                    /// Signal atomic scopes with -(table + 1) value & the atomic syntax
                    /// Jump over scope block regardless
                    /// t positive table ref if actual scope table and negative offset by one to atomic scope
                    /// o is 0 if actual scope table and pointer to `syntax` if atomic scope
                    /// t == 0 is a nil scope - elide.
                    advance()
                    let t = scope[offset].table * (scope[offset].table > 0 ? 1 : table + 1)
                    let o = t > 0 ? 0 : offset
                    advance()
                    if t != 0 { newScope(from: b, p: p, t: t, o: o) }
                    continue serialize
                /// Evaluate scope, handle as necessary
                case .scope: __MajorBug("Evaluation fail - should never hit scope")
                /// Not in the top level scope and hit the end of the table but not done - repeat
                case .none where count != 0 : stack[stackDepth].offset = 0; continue serialize
                ///Done with current scope
                case .none: closeScope(); continue serialize
            }
            advance()
        }
        
        if errored { return .failure(error!) }
        
        stack.removeAll()
        output = self.bufferStack[0].pointee
        return .success(Date.timeIntervalSinceReferenceDate - start + duration)
    }

    
    /// Structure holding state objects for the current scope on the stack
    private struct ScopeState {
        /// Repetition count from block.evalCount - always 0 for the top level scope
        var count: UInt32?// = nil
        /// Current scope's table in the AST
        var table: Int// = 0
        /// Current index in the current table
        var offset: Int// = 0
        var block: LeafBlock?// = nil
        var breakChain: Bool?// = nil
        var allocated: Bool// = false
        var buffer: UnsafeMutablePointer<LKRawBlock>
        var tuple: LKTuple?// = .init()
        var defines: [String: Define]// = [:]

        init(_ buffer: UnsafeMutablePointer<LKRawBlock>) {
            self.block = nil
            self.tuple = nil
            self.buffer = buffer
            self.defines = [:]
            self.count = nil
            self.table = 0
            self.offset = 0
            self.breakChain = nil
            self.allocated = true
        }

        init(from: Self, _ block: LeafBlock, _ tuple: LKTuple?) {
            self.block = block
            self.tuple = tuple
            self.buffer = from.buffer
            self.defines = from.defines
            self.count = nil
            self.table = 0
            self.offset = 0
            self.breakChain = nil
            self.allocated = false
        }
        
        mutating func set(from: Self, _ block: LeafBlock, _ tuple: LKTuple?) {
            self.block = block
            self.tuple = tuple
            self.buffer = from.buffer
            self.defines.removeAll(keepingCapacity: true)
            self.defines = from.defines
            self.count = nil
            self.table = 0
            self.offset = 0
            self.breakChain = nil
            self.allocated = false
        }
    }

    private func newScope(from block: LeafBlock,
                          p params: LKTuple?,
                          t table: Int,
                          o offset: Int) {
        var b: LeafBlock
        if var unsafeBlock = block as? LeafUnsafeEntity {
            unsafeBlock.userInfo = unsafe
            b = unsafeBlock as! LeafBlock
        } else { b = block}
        stackDepth += 1
        if stack.count == stackDepth {
            stack.append(.init(from: stack[stackDepth - 1], b, params)) }
        else {
            stack[stackDepth].set(from: stack[stackDepth - 1], b, params) }
        stack[stackDepth].table = table
        stack[stackDepth].offset = offset
        if b.scopeVariables?.isEmpty == false {
            let ids = b.scopeVariables!.compactMap { x -> String? in
                if x.isValidIdentifier { idCache[x] = .atomic(x) }
                return x.isValidIdentifier ? x : nil
            }
            if !ids.isEmpty {
                allocated = true
                varStackDepth += 1
                varStack.append((.init(ids), .allocate(capacity: 1), nil))
                vars.initialize(to: .init(minimumCapacity: ids.count))
            }
        }
    }

    private func closeScope() {
//        if stack[stackDepth].buffer != stack[stackDepth - 1]
        if allocated, let x = varStack.popLast()?.vars {
            x.deinitialize(count: 1); x.deallocate(); varStackDepth -= 1 }
        stackDepth -= 1
        // Reset breakChain if we were at end of chain
        if let chained = stack[stackDepth + 1].block as? ChainedBlock,
           !nextMatchesChain(type(of: chained)) {
            stack[stackDepth].breakChain = nil
        }
    }
    
    @inline(__always)
    private func nextMatchesChain(_ antecedent: ChainedBlock.Type) -> Bool {
        guard stack[stackDepth].breakChain != nil,
              case .block(_, let n as ChainedBlock, _) = peek?.container,
              type(of: n).chainsTo.contains(where: {$0 == antecedent}) else { return false }
        return true
    }
    
    @inline(__always)
    private func lap() { lapTime = Date().timeIntervalSinceReferenceDate }

    @inline(__always)
    private func evaluateScope() -> Bool? {
        if table * offset < 1 {
            /// All metablocks will always run only once and do not produce variables; can be elided
            if block as? LKMetaBlock != nil { count = 0; return true }

            guard let params = CallValues(block!.sig, tuple, varStack) else {
                void(err("Couldn't evaluate scope parameters")); return nil }
            
            var scopeVariables: [String: LeafData] = [:]
            let scopeValue = stack[stackDepth].block!.evaluateScope(params, &scopeVariables)
            // if evaluate to discard, stop immediately and end the current block
            if scopeValue == 0 { closeScope(); return false }

            // If this is a chained block, we've hit - set breakChain at the previous stack depth
            if block as? ChainedBlock != nil { stack[stackDepth - 1].breakChain = true }
            
            if allocated && !scopeIDs.isEmpty { coalesceVariables(scopeVariables) }
            count = scopeValue != nil ? scopeValue! - 1 : nil
        }
        return true
    }

    private func reEvaluateScope() -> Bool {
        var scopeVariables: [String: LeafData] = [:]
        let scopeValue = stack[stackDepth].block!.reEvaluateScope(&scopeVariables)
        // if evaluate to discard, stop immediately and end the current block
        guard let toGo = scopeValue else {
            error = err("Blocks must not return nil evaluation after having reported a concrete count")
            return false
        }
        if toGo <= 0 { closeScope(); return false }
        if allocated && !scopeIDs.isEmpty { coalesceVariables(scopeVariables) }
        count = toGo - 1
        return true
    }
    
    private func coalesceVariables(_ new: [String: LeafData]) {
        let keys = scopeIDs.map { idCache[$0]! }
        for key in keys {
            let value = new[key.member!] ?? .trueNil
            vars.pointee[key] = value
            if value.celf == .dictionary { expandDict(value, key) }
        }
    }
    
    @inline(__always)
    private func append(_ block: inout LKRawBlock) {
        buffer.pointee.append(&block)
        if let e = buffer.pointee.error { void(err("Serialize Error: \(e)")) }
    }

    @inline(__always)
    private func append(_ data: LeafData) {
        if !data.isNil || data.isTrueNil { stack[stackDepth].buffer.pointee.append(data) } }
    
    private func assignValue(_ key: LKVariable, _ value: LKData) {
        var depth = varStack.count - 1
        while depth >= 0 {
            /// Defined at this level - cache the original
            if let original = varStack[depth].vars.pointee.match(key, contextualize: false) {
                /// Cache the level we're defined at
                let level = depth
                /// If the original value  was a dictionary, decay children at this and higher levels
                if original.celf == .dictionary {
                    while depth < varStack.count {
                        for k in varStack[depth].vars.pointee.keys where k.isDescendent(of: key) {
                            vars.pointee[k] = nil }
                        depth += 1
                    }
                }
                /// Set the new value
                varStack[level].vars.pointee[key] = value
                /// If new value is a dictionary, expand it
                if value.celf == .dictionary { expandDict(value, key, at: level) }
                return
            } else { depth -= 1 }
        }
        /// If we didn't get a hit on uncontextualized but we're assigning value, it means we need to overload self
        varStack[0].vars.pointee[key] = value
        let parent = key.contextualized
        for k in varStack[0].vars.pointee.keys where k.isDescendent(of: parent) {
            varStack[0].vars.pointee[k.uncontextualized] = .trueNil
        }
    }
    
    func bool(_ error: LeafError) -> Bool { self.error = error; return false }
    func void(_ error: LeafError) { self.error = error }
}
