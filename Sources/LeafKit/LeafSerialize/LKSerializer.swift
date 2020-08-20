// MARK: Subject to change prior to 1.0.0 release
// MARK: -
import Foundation

internal final class LKSerializer: LKErroring {
    var error: LeafError? = nil
    
    // MARK: Stored Properties
    private let ast: LeafAST
    /// The original incoming context data
    private var output: UnsafeMutablePointer<LKRawBlock>
    
    private var start: Double
    private var lapTime: Double
    private var threshold: Double
    private var tickCount: UInt8 = 0
    
    private var idCache: [String: LKVariable] = [:]
    
    private var stack: ContiguousArray<ScopeState> = []
    private var stackDepth: Int = 0
    
    private var varStack: LKVarStack = []
    private var varStackDepth: Int = 0
    
    // MARK: Computed Properties
    private var table: Int { stack[stackDepth].table }
    private var scope: ContiguousArray<LKSyntax> { ast.scopes[table] }
    private var defines: [String: Define] { stack[stackDepth].defines }
    private var breakChain: Bool? { get { stack[stackDepth].breakChain } set { stack[stackDepth].breakChain = newValue } }
    private var scopeIDs: Set<String> { varStack[varStackDepth].ids }
    private var vars: LKVarTablePointer { varStack[varStackDepth].vars }
    private var allocated: Bool { get { stack[stackDepth].allocated } set { stack[stackDepth].allocated = newValue} }
    private var count: UInt32? { get {stack[stackDepth].count} set { stack[stackDepth].count = newValue } }
    private var block: LeafBlock? { stack[stackDepth].block }
    private var tuple: LKTuple? { stack[stackDepth].tuple }

    private var offset: Int {
        get { stack[stackDepth].offset }
        set { stack[stackDepth].offset = newValue }
    }
    
    @inline(__always)
    private var cutoff: Bool {
        tickCount &+= 1
        if tickCount == 0 { lap() }
        if threshold < (lapTime - start) { error = err("Execution timed out") }
        return errored
    }
    
    private var peek: LKSyntax? { scope.count > offset ? scope[offset] : nil }

    init(_ ast: LeafAST, _ context: [String: LKData], _ output: LKRawBlock.Type) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LKConf.timeout
        self.varStack.reserveCapacity(Int(ast.info.stackDepths.overallMax))
        self.varStack.append(([], LKVarTablePointer.allocate(capacity: 1)))
        self.output = UnsafeMutablePointer<LKRawBlock>.allocate(capacity: 1)
        self.output.initialize(to: output.instantiate(size: ast.info.averages.size,
                                                      encoding: LKConf.encoding))
        self.stack = .init(repeating: .init(self.output),
                           count: Int(ast.info.stackDepths.overallMax))
        
        vars.initialize(to: .init(minimumCapacity: context.count * 2))
        vars.pointee[.`self`] = .dictionary(context)
        expandDict(.dictionary(context), .`self`)
    }
    
    init(_ ast: LeafAST, contexts: [LKVariable: LKData], _ output: LKRawBlock.Type) {
        self.ast = ast
        self.start = Date.distantFuture.timeIntervalSinceReferenceDate
        self.lapTime = Date.distantPast.timeIntervalSinceReferenceDate
        self.threshold = LKConf.timeout
        self.varStack.reserveCapacity(Int(ast.info.stackDepths.overallMax))
        self.varStack.append(([], LKVarTablePointer.allocate(capacity: 1)))
        self.output = UnsafeMutablePointer<LKRawBlock>.allocate(capacity: 1)
        self.output.initialize(to: output.instantiate(size: ast.info.averages.size,
                                                      encoding: LKConf.encoding))
        self.stack = .init(repeating: .init(self.output),
                           count: Int(ast.info.stackDepths.overallMax))
        vars.initialize(to: .init(minimumCapacity: contexts.count * 2))
        vars.pointee = contexts
        for (key, value) in vars.pointee where value.celf == .dictionary {
            expandDict(value, key) }
    }

    deinit {
        vars.deinitialize(count: 1)
        vars.deallocate()
        output.deinitialize(count: 1)
        output.deallocate()
    }

    private func expandDict(_ data: LKData,
                            _ base: LKVariable = .`self`) {
        var recurse: [(LKVariable, LKData)] = []
        data.dictionary.map {
            for (identifier, value) in $0 {
                let key: LKVariable = base.extend(with: identifier)
                vars.pointee[key] = value
                if value.celf == .dictionary { recurse.append((key, value)) }
            }
        }
        while let x = recurse.popLast() { expandDict(x.1, x.0) }
    }

    func serialize(buffer output: inout LKRawBlock,
                   timeout: Double? = nil) -> Result<Double, LeafError> {
        guard !ast.scopes[0].isEmpty else { return .success(0) }
        if let timeout = timeout { threshold = timeout }

        start = Date().timeIntervalSinceReferenceDate
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

                offset += 1
                closeScope()
                continue
            }

            let next = peek
            if next == nil && stackDepth == 0 { break }
            switch next?.container {
                // Basic cases. Append evaluated atomics/raws to the current buffer
                case .raw(var raw)           : append(&raw)
                case .passthrough(let param) :
                    if case .expression(let exp) = param,
                       exp.form.exp == .assignment {
                        let result = exp.evalAssignment(varStack)
                        switch result {
                            case .success(let val): assignValue(val.0, val.1)
                            case .failure(let err): return .failure(err)
                        }
                    } else { append(param.evaluate(varStack)) }
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
                                        varStack.append(([], .allocate(capacity: 1)))
                                        vars.initialize(to: .init())
                                    }
                                    vars.pointee[.define(id)] = set ? .init(.evaluate(param: param.container)) : nil
                                }
                                offset += 2
                                continue serialize
                            case .evaluate :
                                let evaluate = meta as! Evaluate
                                offset += 2
                                /// If the definition exists, open a new stack and point it at the ref scope or atomic defintion
                                if let jump = defines[evaluate.identifier] {
                                    let land = ast.scopes[jump.table][jump.row]
                                    let t = land.table * (land.table > 0 ? 1 : jump.table + 1)
                                    let o = t > 0 ? 0 : jump.row
                                    if t != 0 { newScope(from: evaluate, p: nil, t: t, o: o) }
                                /// or if no definition but evaluate has a default value roll back one and serialize that
                                } else if evaluate.defaultValue != nil { offset -= 1 }
                                continue serialize
                        }
                    }
                    /// Otherwise actual scopes: Next check if a chained block and not at end of scope.
                    if let chained = b as? ChainedBlock {
                        if breakChain == true {
                            offset += 2
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
                    offset += 1
                    let t = scope[offset].table * (scope[offset].table > 0 ? 1 : table + 1)
                    let o = t > 0 ? 0 : offset
                    offset += 1
                    if t != 0 { newScope(from: b, p: p, t: t, o: o) }
                    continue serialize
                /// Evaluate scope, handle as necessary
                case .scope: __MajorBug("Evaluation fail - should never hit scope")
                /// Not in the top level scope and hit the end of the table but not done - repeat
                case .none where count != 0 : offset = 0; continue serialize
                ///Done with current scope
                case .none: closeScope(); continue serialize
            }
            offset += 1
        }
        stack.removeAll()
        output = self.output.pointee

        return errored ? .failure(error!)
                       : .success(Date.timeIntervalSinceReferenceDate - start)
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
        stackDepth += 1
        if stack.count == stackDepth {
            stack.append(.init(from: stack[stackDepth - 1], block, params)) }
        else {
            stack[stackDepth].set(from: stack[stackDepth - 1], block, params) }
        stack[stackDepth].table = table
        stack[stackDepth].offset = offset
        if block.scopeVariables?.isEmpty == false {
            let ids = block.scopeVariables!.compactMap { x -> String? in
                if x.isValidIdentifier { idCache[x] = .atomic(x) }
                return x.isValidIdentifier ? x : nil
            }
            if !ids.isEmpty {
                allocated = true
                varStackDepth += 1
                varStack.append((.init(ids), .allocate(capacity: 1)))
                vars.initialize(to: .init(minimumCapacity: ids.count))
            }
        }
    }

    private func closeScope() {
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
        do { try stack[stackDepth].buffer.pointee.append(&block) }
        catch { void(err("Serializing Error")) }
    }

    @inline(__always)
    private func append(_ data: LeafData) { stack[stackDepth].buffer.pointee.append(data) }
    
    private func assignValue(_ key: LKVariable, _ value: LKData) {
        /// If the variable already exists and was a dictionary, decay children
        if vars.pointee[key]?.celf == .dictionary {
            vars.pointee.keys.forEach {
                if $0.isDescendent(of: key) { vars.pointee[$0] = nil }                
            }
        }
        vars.pointee[key] = value
        expandDict(value, key)
    }
    
    func bool(_ error: LeafError) -> Bool { self.error = error; return false }
    func void(_ error: LeafError) { self.error = error }
}
