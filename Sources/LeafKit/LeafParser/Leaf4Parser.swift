// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation
import NIO

internal struct Leaf4Parser {
    // MARK: - Internal Only
    
    let name: String
    
    init(_ name: String, _ tokens: [LeafToken]) {
        self.entities = LeafConfiguration.entities
        self.name = name
        self.tokens = tokens
        self.rawStack = [entities.raw.instantiate(data: nil, encoding: .utf8)]
    }
    
    mutating func parse() throws -> Leaf4AST {
        var more = true
        while more { more = advance() }
        if let error = error { throw error }
        return Leaf4AST(name,
                        scopes,
                        defines,
                        inlines,
                        underestimatedSize)
    }

    // MARK: - Private Only
    /// The active entities reference object
    private var entities: LeafEntities
    /// The incoming tokens
    private var tokens: [LeafToken]
    
    /// The AST scope tables
    private var scopes: [[Leaf4Syntax]] = [[]]
    /// References to all `define` blocks
    private var defines: [Leaf4AST.ScopeReference] = []
    /// References to all `inline` blocks
    private var inlines: [(inline: Leaf4AST.ScopeReference, process: Bool, at: Date)] = []
    private var underestimatedSize: UInt64 = 0
    
    private var scopeStack = [0]
    private var currentScope: Int { scopeStack.last! }
    
    private var openBlocks: [(name: String, block: LeafFunction.Type)] = []
    private var lastBlock: Int? { openBlocks.indices.last }
        
    private var offset: Int = 0
    private var error: LeafError? = nil { willSet {  } }
    
    private var peek: LeafToken? { offset < tokens.count ? tokens[offset] : nil }
    
    private var rawStack: [RawBlock]
    
        /// Process the next `LeafToken` or multiple tokens.
    private mutating func advance() -> Bool {
        guard let current = pop(), error == nil else { return false }
        
        // Get the easy stuff out of the way first...
        guard current == .tagIndicator else {
            // 1. Anything that isn't raw is invalid and Lexer shouldn't have produced it
            guard case .raw(var string) = current else { __MajorBug(.malformedToken) }
            // 2. Aggregate all consecutive raws into one
            while case .raw(let more) = peek { string += more; pop() }
            return appendRaw(string)
        }
        
        // 3. Off chance it's tI @ EOF - append a raw tag indicator
        guard peek != nil else { return appendRaw(Character.tagIndicator.description) }
        
        // 4. .tagIndicator is *always* followed by .tag - anything else is Lexer error
        guard case .tag(let tag) = pop(), tag != .some("") else { __MajorBug(.malformedToken) }
        
        // 5. Everything now is either anonymous, function, or block:
        
        // 5A. Catch anonymous (nil) tags
        guard let tagName = tag else {
            // Check to decay trailing .scopeIndicator to raw `:`
            defer { if peek == .scopeIndicator { decayTokenTo(":") } }
            let tuple = parseTuple(nil)
            guard error == nil else { return false }
            // Validate tuple is single parameter, append or evaluate & append raw if invariant
            guard tuple?.count ?? 0 <= 1 else {
                return parseError("Anonymous tag can't have multiple parameters") }
            if let tuple = tuple, let value = tuple[0] {
                guard case .value(let data) = value.container,
                      data.resolved && data.invariant else { append(value); return true }
                appendRaw(data)
            }
            return true
        }
        
        if let meta = entities.blockFactories[tagName] as? MetaBlock.Type {
            return handleMeta(tagName, meta, parseTuple(tagName)) }
        
        let blockBypass: Bool
        if let b = entities.blockFactories[tagName], b.parseSignatures != nil {
            blockBypass = true
        } else { blockBypass = false }
        // 5B. Parse the parameter tuple for the tag, if parameters exist
        let tuple = parseTuple(tagName, forParse: blockBypass)
        guard error == nil else { return false }
        
        // 5C. Catch non-block tags
        guard peek == .scopeIndicator else {
            // 5D. A normal function call (without a trailing colon)
            if !tagName.hasPrefix("end") && !entities.blockFactories.keys.contains(tagName) { return appendFunction(tagName, tuple) }
            
            // 5E. A full-stop "end*" tag
            guard let lastBlock = lastBlock else {
                // 5F. No open blocks on the stack. Failure to close
                return parseError("No open block to close matching #\(tagName)")
            }
            
            let openTag = tagName.dropFirst(3)
            var canClose = false
            var pass = 0
            
            // 5G. Last open block *must* match or it *must* be a chained block
            while lastBlock - pass >= 0 && !canClose {
                let currentBlock = openBlocks[lastBlock - pass]
                // Match either immediate precedent or head of chain, stop.
                if openTag == currentBlock.name { canClose = true; break }
                // Not a match. Continue down stack if the current block is an
                // interstitial chained block (not an opening chainer).
                if let chain = currentBlock.block as? ChainedBlock.Type,
                   !chain.chainsTo.isEmpty { pass += 1 }
                // Head of chain was not a match, stop.
                else { break }
            }
            // 5H. No matching open block on the stack. Failure to close.
            guard canClose else { return parseError("No open block to close matching #\(tagName)") }
            // Decay chained blocks from the open stack if we were in one.
            var closeRaw = false
            for _ in 0...pass { closeRaw = openBlocks.removeLast().block == RawSwitch.self }
            // Only one scope will be open, even for chains
            guard closeBlock(closeRaw) else { return false }
            // 5I. Successfully closed block.
            return true
        }
        
        // 5J. Try to make or close/make a block (or decay to function)
        let result = entities.validateBlock(tagName, tuple)
        
        // TODO: If the call parameters are all literal values evalute
        //       - EG: see/warn if scope is discarded (eg #if(false))
        
        guard case .success(let block) = result else {
            // 5K. Any failure to make, short of "not a block", is an error
            if case .failure(let reason) = result,
               !reason.contains("not a block") { return parseError(reason) }
            // 5L. A normal function call with a trailing colon, decay `:`
            decayTokenTo(":")
            return appendFunction(tagName, tuple)
        }
        
        pop() // Dump scope indicator now
        
        // 5M. If new block is chained type, ensure connection and close current scope
        if let chained = type(of: block.0) as? ChainedBlock.Type,
           !chained.chainsTo.isEmpty {
            // chained interstitial - must be able to close current block
            guard let previous = openBlocks.last?.block as? ChainedBlock.Type,
                  chained.chainsTo.contains(where: {$0 == previous})
            else { return parseError("No open block for #\(tagName) to close") }
            guard closeBlock() else { return false }
        }
        
        // 5N. Open the new block
        return openBlock(tagName, block.0 as! LeafBlock, block.1)
    }

    @discardableResult
    private mutating func pop() -> LeafToken? {
        if let next = peek { offset += 1; return next }; return nil
    }
    
    /// Decay the next token up to a specified raw string
    private mutating func decayTokenTo(_ string: String) {
        if peek != nil { tokens[offset] = .raw(string) }
    }
    
    /// Append a passthrough syntax object to the current scope and return true to continue parsing
    @discardableResult
    private mutating func append(_ syntax: LeafParameter) -> Bool {
        scopes[currentScope].append(.passthrough(syntax))
        let estimate: UInt64
        switch syntax.container {
            case .expression, .function,
                 .variable, .value : estimate = 16
            case .operator, .tuple : estimate = 0
            case .keyword(let k)   : estimate = k.isBooleanValued ? 4 : 0
        }
        underestimatedSize += estimate
        return true
    }
    
    /// Append a new raw block.
    @discardableResult
    private mutating func appendRaw(_ raw: String) -> Bool {
        var buffer = ByteBufferAllocator().buffer(capacity: raw.count)
        buffer.writeString(raw)
        underestimatedSize += UInt64(buffer.readableBytes)
        var newRaw = type(of: rawStack.last!).instantiate(data: buffer, encoding: .utf8)
        let checkAt = scopes[currentScope].count - 2
        let blockCheck: Bool
        if checkAt >= 0, case .block = scopes[currentScope][checkAt].container { blockCheck = true }
        else { blockCheck = false }
        // If previous is raw and it's not a scope atomic, concat or append new
        if case .raw(var previous) = scopes[currentScope].last?.container,
           !blockCheck {
            try! previous.append(&newRaw)
            scopes[currentScope][checkAt + 1] = .raw(previous)
        } else { scopes[currentScope].append(.raw(buffer)) }
        return true
    }
    
    /// Append a new raw block.
    @discardableResult
    private mutating func appendRaw(_ data: LeafData) -> Bool {
        let checkAt = scopes[currentScope].count - 2
        let blockCheck: Bool
        if checkAt >= 0, case .block = scopes[currentScope][checkAt].container { blockCheck = true }
        else { blockCheck = false }
        // If previous is raw and it's not a scope atomic, concat or append new
        if case .raw(var previous) = scopes[currentScope].last?.container,
           !blockCheck {
            underestimatedSize -= previous.byteCount
            previous.append(data)
            scopes[currentScope][checkAt + 1] = .raw(previous)
            underestimatedSize += previous.byteCount
        } else {
            let buffer = ByteBufferAllocator().buffer(capacity: 0)
            var newRaw = type(of: rawStack.last!).instantiate(data: buffer, encoding: .utf8)
            newRaw.append(data)
            underestimatedSize += newRaw.byteCount
            scopes[currentScope].append(.raw(newRaw))
        }
        return true
    }
    
    /// If the tag name and parameters can create a valid function call, true and append or set error
    private mutating func appendFunction(_ t: String, _ p: LeafTuple?) -> Bool {
        let result = entities.validateFunction(t, p)
        underestimatedSize += 16
        switch result {
            case .failure(let r): return parseError("\(t) couldn't be parsed: \(r)")
            case .success(let f): return append(.function(t, f.0, f.1))
        }
    }
    
    /// Open a new block scope.
    private mutating
    func openBlock(_ n: String, _ b: LeafBlock, _ p: LeafTuple?) -> Bool {
        // New syntaxes in current scope
        scopes[currentScope].append(.block(n, b, p))
        scopes[currentScope].append(.scope(scopes.count))
        openBlocks.append((n, type(of: b))) // Push block onto open stack
        scopes.append([])                   // Create new scope
        scopeStack.append(scopes.count - 1) // Push new scope reference
        return true
    }
    
    /// Close the current scope. If the closing scope is empty or single element, remove its table and inline in place of scope.
    private mutating func closeBlock(_ rawBlock: Bool = false) -> Bool {
        guard currentScope > 0 else { return parseError("Can't close top scope") }
        if scopes[currentScope].count < 2 {
            let decayed = scopes.removeLast()
            scopeStack.removeLast()
            guard case .scope = scopes[currentScope].last?.container else {
                __MajorBug("Scope change didn't find a scope reference")
            }
            scopes[currentScope].removeLast()
            scopes[currentScope].append(decayed.isEmpty ? .scope(nil) : decayed[0] )
        } else {
            scopeStack.removeLast()
        }
        if rawBlock { rawStack.removeLast() }
        return true
    }
    
    private mutating func handleMeta(_ name: String,
                                     _ meta: MetaBlock.Type,
                                     _ tuple: LeafTuple?) -> Bool {
        let isBlock: Bool = peek == .scopeIndicator
        if isBlock { pop() }
        switch meta.form {
            case .define:
                guard let tuple = tuple, tuple.count == 2 - (isBlock ? 1 : 0),
                      case .variable(let v) = tuple[0]?.container, v.atomic,
                      tuple.count == 2 ? (tuple[1]!.isValued) : true
                else { return parseError("#\(name) \(Define.warning)") }
                let definition = Define(identifier: v.member!,
                                        table: currentScope,
                                        row: scopes[currentScope].count + 1)
                if isBlock { _ = openBlock(name, definition, tuple) }
                else {
                    let value = tuple[1]!
                    scopes[currentScope].append(.block(name, definition, tuple))
                    scopes[currentScope].append(.passthrough(value))
                }
                // Init with identifier and jump point to be evaluated
                defines.append(.init(identifier: v.member!,
                                     table: definition.table,
                                     row: definition.row + 1))
            case .evaluate:
                guard let tuple = tuple, tuple.count == 1, let param = tuple[0] else {
                    return parseError("#\(name) \(Evaluate.warning)") }
                let definedName: String
                let defaultValue: LeafParameter?
                switch param.container {
                    case .expression(let e) where e.op == .nilCoalesce:
                        guard case .variable(let v) = e.lhs?.container,
                              v.atomic, let coalesce = e.rhs, coalesce.isValued
                        else { return parseError("#\(name) \(Evaluate.warning)") }
                        definedName = v.member!
                        defaultValue = coalesce
                    case .variable(let v) where v.atomic:
                        definedName = String(v.member!)
                        defaultValue = nil
                    default: return parseError("#\(name) \(Evaluate.warning)")
                }
                scopes[currentScope].append(.block(name, Evaluate(identifier: definedName), tuple))
                scopes[currentScope].append(defaultValue == nil ? .scope(nil)
                                                : .passthrough(defaultValue!))
                if isBlock { appendRaw(Character.tagIndicator.description) }
            case .inline:
                guard let tuple = tuple, (1...2).contains(tuple.count),
                      case .string(let file) = tuple[0]?.data?.container
                else { return parseError("#\(name) requires a string literal argument for the file") }
                var process = false
                var raw: String? = nil
                if tuple.count == 2 {
                    guard tuple.labels["as"] == 1, let behavior = tuple[1]?.container
                    else { return parseError("#\(name)(\"file\", as: type) where type is `leaf` or a raw handler") }
                    if case .keyword(.leaf) = behavior { process = true }
                    else if case .variable(let v) = behavior, v.atomic,
                            let handler = String(v.member!) as String?,
                            handler == "raw" || entities.rawFactories[handler] != nil {
                        raw = handler != "raw" ? handler : nil
                    } else { return parseError("#\(name)(\"file\", as: type) where type is `leaf`, `raw`, or a named raw handler") }
                } else { process = true }
                let inline = Inline(file, process: process, rawIdentifier: process ? nil : raw )
                inlines.append((inline: .init(identifier: file,
                                              table: currentScope,
                                              row: scopes[currentScope].count),
                                process: inline.process,
                                at: .distantFuture))
                scopes[currentScope].append(.block(name, inline, tuple))
                scopes[currentScope].append(.scope(nil))
                if isBlock {
                    if process { appendRaw(Character.tagIndicator.description) }
                }
            case .rawSwitch:
                guard tuple?.isEmpty ?? true else { return parseError("Using #\(name)() with parameters is not yet supported") }
                if isBlock {
                    // When enabled, type will be picked from parameter & params will be passed
                    rawStack.append(type(of: rawStack.last!).instantiate(data: nil, encoding: .utf8))
                    return openBlock(name, RawSwitch(type(of: rawStack.last!), .init()), tuple)
                }
                else { appendRaw("") }
        }
        return true
    }

    enum VarState: Int, Comparable {
        case start, uncertainScope, scopeRequired, uncertainVariable, chain
        static func <(lhs: VarState, rhs: VarState) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    
    /// Try to read parameters. Return nil if no parameters present. Nil for `function` if for expression.
    private mutating func parseTuple(_ function: String?, forParse: Bool = false) -> LeafTuple? {
        if peek == .parametersStart { pop() } else { return nil }
        
        // Stacks
        var functions: [String?] = []
        var tuples: [LeafTuple] = []
        var labels: [String?] = []
        var states: [VarState] = []
        var complexes: [[LeafParameter]] = []
        
        // Conveniences to current stacks
        var currentFunction: String? {
            get { functions.last! }
            set { functions[functions.indices.last!] = newValue}
        }
        var currentTuple: LeafTuple {
            get { tuples.last! }
            set { tuples[tuples.indices.last!] = newValue }
        }
        var currentLabel: String? {
            get { labels.last! }
            set { labels[labels.indices.last!] = newValue}
        }
        var currentState: VarState {
            get { states.last! }
            set { states[states.indices.last!] = newValue }
        }
        var currentComplex: [LeafParameter] {
            get { complexes.last! }
            set { complexes[complexes.indices.last!] = newValue }
        }
        var atomicComplex: LeafParameter? {
            currentComplex.count > 1     ? nil
                : currentComplex.isEmpty ? .value(.trueNil)
                                         : currentComplex[0]
        }
        
        var forFunction: Bool { currentFunction != nil }
        
        // If parsing for a block signature and normal evaluation fails, flag to
        // attempt to retry without complex expression sanity for top level
        var retrying: Bool? = forParse ? false : nil
        
        /// Evaluate the current complex expression into an atomic expression or fail, and close the current complex and label states
        @discardableResult
        func tupleAppend() -> Bool {
            guard currentComplex.count <= 1 else {
                return parseError("Couldn't resolve parameter") }
            defer { currentState = .start; currentLabel = nil;
                    complexes.removeLast(); complexes.append([]) }
            guard !currentComplex.isEmpty else { return true }
            // Get the current count of parameters in the current tuple
            let count = currentTuple.values.count
            // Add the parameter to the current tuple's values
            tuples[tuples.indices.last!].values.append(atomicComplex!)
            // Get the current label if one exists, return if it's nil
            guard let label = currentLabel else { return true }
            // Add the label to the tuple's labels for the new position
            tuples[tuples.indices.last!].labels[label] = count
            return true
        }
        
        @discardableResult
        func complexAppend(_ a: LeafParameter, sanity: Bool = true) -> Bool {
            var blockParse = false
            if let bypass = retrying, bypass { blockParse = true }
            if sanity {
                if currentState == .uncertainVariable {
                    guard let variable = makeVariable()
                        else { return parseError("Couldn't close a variable identifier") }
                    complexes[complexes.indices.last!].append(.variable(variable))
                }
                if let op = a.operator, op.infix {
                    guard !currentComplex.isEmpty, currentComplex.last!.isValued
                        else { return parseError("Can't operate on non-valued parameter") }
                } else if !currentComplex.isEmpty, !blockParse {
                    guard let op = currentComplex.last?.operator, !op.unaryPostfix
                        else { return parseError("Missing operator between parameters") }
                }
            }
            complexes[complexes.indices.last!].append(a)
            return true
        }
        
        func complexDrop(_ d: Int) { complexes[complexes.indices.last!].removeLast(d) }
        
        // Open a new tuple
        func newTuple(_ function: String? = nil) {
            functions.append(function)
            tuples.append(.init())
            labels.append(nil)
            states.append(.start)
            complexes.append([])
        }
        
        func makeVariable() -> LeafVariable? {
            if currentState < .uncertainVariable { parseError("No valid variable identifier"); return nil }
            let valid = LeafVariable(openScope, openMember, openPath.isEmpty ? nil : openPath)
            guard let variable = valid else { parseError("Invalid variable identifier"); return nil }
            currentState = .start
            openScope = nil; openMember = ""; openPath = []; needIdentifier = false;
            return variable
        }
        
        func resolveSubscript() {
            guard let last = currentComplex.indices.last,
                  currentComplex.count >= 3, currentComplex[last].isValued,
                  case .operator(.subScript) = currentComplex[last - 1].container
            else { parseError("Can't close subscript"); return }
            guard let parameter = express([currentComplex[last - 2],
                                       .operator(.subScript),
                                       currentComplex[last]])
            else { parseError("Couldn't subscript"); return }
            complexDrop(3)
            complexAppend(parameter, sanity: false)
        }
        
        /// Generate a LeafExpression, or if an evaluable, invariant expression, a value
        func express(_ params: [LeafParameter]) -> LeafParameter? {
            if let expression = LeafExpression.express(params) {
                if expression.invariant && expression.resolved
                   { return .value(expression.evaluate()) }
                return .expression(expression)
            } else if let expression = LeafExpression.expressAny(params) {
                return .expression(expression)
            }
            return nil
        }
        
        func operatorState(_ op: LeafOperator) {
            switch op {
                // Variable scoping / Method accessors
                case .scopeMember:
                    if !needIdentifier, currentState >= .uncertainVariable { needIdentifier = true }
                    else if currentComplex.last?.isValued ?? false { currentState = .chain }
                    else { parseError("Ambiguous accessor - Expected identifier") }
                case .scopeRoot:
                    if currentState > .uncertainScope { parseError("Can't reference a new variable"); break }
                    currentState = .scopeRequired; needIdentifier = true
                case .subOpen:
                    // check for an open variable & close it
                    if currentState == .uncertainVariable {
                        guard let variable = makeVariable() else { break }
                        complexAppend(.variable(variable))
                    }
                    complexAppend(.operator(.subScript), sanity: false)
                    needIdentifier = true
                case .subClose:
                    if currentState == .uncertainVariable {
                        guard let variable = makeVariable() else { break }
                        complexAppend(.variable(variable))
                    }
                    resolveSubscript()
                // TODO: Assignment, evaluate
                case .assignment, .evaluate: parseError("\(op) not yet implemented")
                default:
                    complexAppend(.operator(op))
                    needIdentifier = true
                    currentState = .start
            }
        }
        
        /// Add an atomic variable part to label, scope, member, or part,, dependent on state
        func variableState(_ part: String, parseBypass: Bool = false) {
            // if parseBypass, immediately decay to atomic identifier and return
            if parseBypass {
                complexAppend(.variable(.atomic(part)))
                retrying = false
                return
            }
            
            // decay to label identifier if first element in a complex
            // expression and consume the indicator - only for function parameters
            if forFunction, currentComplex.isEmpty, peek == .scopeIndicator
                { currentLabel = part; currentState = .uncertainScope; pop(); return }
            
            guard needIdentifier else { __MajorBug("Parser error") }
            needIdentifier = false
            
            switch currentState {
                case .scopeRequired: openScope = part; currentState = .uncertainVariable
                case .start,
                     .uncertainScope,
                     .uncertainVariable:
                        currentState = .uncertainVariable
                    if openMember.isEmpty { openMember = part } else { openPath.append(part) }
                case .chain:
                    complexAppend(.value(.string(part)))
                    resolveSubscript()
            }
        }
        
        /// Add a new function to the stack
        func functionState(_ function: String) {
            guard needIdentifier, peek == .parametersStart else { __MajorBug("Parser error") }
            // If we were in the middle of a variable, manually close it and
            // append to expression, bypassing sanity checks on operators. When
            // the next tuple for this function's parameters close, we'll
            // rewrite the closed variable into the first parameter's tuple.
            if currentState == .uncertainVariable {
                guard let valid = makeVariable() else { return }
                complexAppend(.variable(valid), sanity: false)
                currentState = .chain
            }
            newTuple(function)
            pop()
        }
        
        /// Attempt to resolve the current complex expression
        func closeComplex(_ open: Bool) -> Bool {
            // pull the current complex off the stack
            guard var exp = complexes.popLast() else { return false }
            
            // check for an open variable & close it
            if currentState == .uncertainVariable {
                guard !open else { return parseError("Unexpected accessor; expected property or method") }
                guard let variable = makeVariable() else { return false }
                exp.append(.variable(variable))
            }
            
            func countOpsWhere(_ check: (LeafOperator) -> Bool) -> Int {
                exp.reduce(0, { $0 + ($1.operator.map {check($0) ? 1 : 0} ?? 0) }) }
            func lastOpWhere(_ check: (LeafOperator) -> Bool) -> Int? {
                for (i, p) in exp.enumerated().reversed() {
                    if let op = p.operator, check(op) { return i } }
                return nil }
            func wrapInfix(_ i: Int) -> Bool {
                guard 0 < i && i < exp.count - 1,
                      let wrap = express([exp[i - 1], exp[i], exp[i + 1]]) else { return false}
                exp[i - 1] = wrap; exp.remove(at: i); exp.remove(at: i); return true
            }
            func wrapNot(_ i: Int) -> Bool {
                guard exp.indices.contains(i + 1),
                      let wrap = express([exp[i], exp[i + 1]]) else { return false }
                exp[i] = wrap; exp.remove(at: i + 1); return true
            }
            
            var opCount: Int { countOpsWhere { _ in true } }
            
            var ops = opCount
            // Next wrap evaluation operations
            if ops > 0 {
                wrapOps:
                for map in LeafOperator.evalPrecedenceMap {
                    while let index = lastOpWhere(map.check) {
                        if (map.infixed ? !wrapInfix(index) : !wrapNot(index)) { break wrapOps }
                        ops -= 1; if opCount == 0 { break wrapOps }
                    }
                }
            }
            
            // Customs expressions can still be at most 3-part, anything more is invalid
            if exp.count > 3 { return false }
            else if exp.count > 1 {
                // Only blocks may have non-atomic parameters, so any complex
                // expression above the first tuple must be atomic - but if we're retrying, bypass
                if tuples.count > 1 || currentFunction == nil, !(retrying ?? false) { return false }
                // Blocks may parse custom expressions so wrap into any expression
                exp = [.expression(LeafExpression.expressAny(exp)!)]
            }
            complexes.append(exp)
            return true
        }
        
        // Atomic states
        var needIdentifier = true
        
        var openScope: String? = nil
        var openMember: String = ""
        var openPath: [String] = []
               
        // open the first complex expression, param label, and tuple
        newTuple(function)
        
        func resolveExpression() {
            guard let tuple = tuples.popLast(), tuple.values.count <= 1 else {
                parseError("Expressions must return a single value"); return }
            if tuple.count == 1, let value = tuple.values.first { complexAppend(value) }
        }
    
        while error == nil, let next = peek {
            pop()
            switch next {
                case .parameter(let p)         :
                    switch p {
                        case .operator(let o)  : operatorState(o)
                        case .variable(let v)  : variableState(v, parseBypass: !(retrying ?? true))
                        case .function(let f)  : functionState(f)
                        case .literal(let l)   : complexAppend(.value(l.leafData))
                        case .keyword(let k)   :
                            if k == .`self` {
                                openScope = LeafVariable.selfScope
                                currentState = .uncertainVariable
                                needIdentifier = false
                            } else { complexAppend(.keyword(k)) }
                    }
                case .parameterDelimiter       :
                    // Try to close the current complex expression and append to the current tuple
                    guard closeComplex(needIdentifier) else { if error == nil { parseError("Couldn't close expression") } ; break }
                    tupleAppend()
                case .parametersEnd            :
                    // Try to close the current complex expression, append to the current tuple,
                    // and close the current tuple
                    let chained = states.count > 1 ? states[states.indices.last! - 1] == .chain : false
                    guard closeComplex(needIdentifier) else { if error == nil { parseError("Couldn't close expression") } ; break }
                    guard tupleAppend() else { break }
                    guard tuples.count > 1 || chained else { return currentTuple }
                    let function = functions.removeLast()
                    var tuple = tuples.removeLast()
                    labels.removeLast()
                    complexes.removeLast()
                    switch function {
                        // expression
                        case .none where retrying == nil:
                            currentComplex.append(tuple.isEmpty ? .value(.trueNil) : tuple.values[0])// expression
                        // tuple where we're in block parsing & top-level
                        case .none:
                            currentComplex.append((tuple.isEmpty && tuples.count != 1) ? .value(.trueNil) : .tuple(tuple))
    
                        // Method function
                        case .some(let m) where chained:
                            guard !currentComplex.isEmpty, let operand = currentComplex.popLast(),
                                  operand.isValued else { parseError("Can't call method on non-valued parameter"); break }
                            tuple.labels = tuple.labels.mapValues { $0 + 1 }
                            tuple.values.insert(operand, at: 0)
                            let result = entities.validateMethod(m, tuple)
                            switch result {
                                case .failure(let r): parseError("\(m) couldn't be parsed: \(r)")
                                case .success(let M): complexAppend(.function(m, M.0, M.1))
                            }
                        // Atomic function
                        case .some(let f):
                            let result = entities.validateFunction(f, tuple)
                            switch result {
                                case .failure(let r): parseError("\(f) couldn't be parsed: \(r)")
                                case .success(let F): complexAppend(.function(f, F.0, F.1))
                            }
                    }
                    states.removeLast()
                case .parametersStart          :
                    // This should only occur hit if opening paren is consciously
                    // wrapping an expression - Not yet valid in a variable
                    // chain until evaluate exists
                    guard currentState < .scopeRequired else {
                        parseError("Can't use expressions in variable identifier"); break }
                    currentState = .start
                    newTuple()
                case .scopeIndicator           : parseError("`:` only usable as label separator for function parameters")
                case .tag, .tagIndicator, .raw : __MajorBug("Lexer produced \(next) inside parameters")
            }
            
            // If this is for a block and we errored, retry once
            if error != nil, forParse, let r = retrying, !r {
                error = nil; offset -= 1; retrying = true }
        }
        // Error states from parameter parsing
        if error != nil { return nil }
        // Error state from grammatically correct but unclosed parameters
        if tuples.count != 1 { parseError("Couldn't close parameters") }
        return tuples.popLast()
    }
    
    /// Set parsing error state and return false to halt parsing
    @discardableResult
    private mutating func parseError(_ reason: String,
                                     file: String = #file,
                                     function: String = #function,
                                     line: UInt = #line,
                                     column: UInt = #column) -> Bool {
        error = LeafError(.unknownError(reason),
                          file: String(file.split(separator: "/").last ?? ""),
                          function: function, line: line, column: column)
        return false
    }
}


private extension String {
    static let malformedToken = "Lexer produced malformed tokens"
}
