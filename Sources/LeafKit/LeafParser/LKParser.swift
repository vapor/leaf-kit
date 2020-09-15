import Foundation
import NIO

internal struct LKParser: LKErroring {
    // MARK: - Internal Only

    let key: LeafASTKey
    var error: LeafError? = nil

    init(_ key: LeafASTKey, _ tokens: [LKToken]) {
        self.entities = LKConf.entities
        self.key = key
        self.tokens = tokens
        self.rawStack = [entities.raw.instantiate(data: nil, encoding: .utf8)]
    }

    mutating func parse() throws -> LeafAST {
        var more = true
        while more { more = advance() }
        if !errored && !openBlocks.isEmpty {
            error = err("[\(openBlocks.map { "#\($0.name)(...):" }.joined(separator: ", "))] still open at EOF")
        }
        if let error = error { throw error }
        return LeafAST(key,
                       scopes,
                       defines,
                       inlines,
                       requiredVars,
                       underestimatedSize,
                       scopeDepths)
    }

    // MARK: - Private Only
    /// The active entities reference object
    private let entities: LeafEntities
    /// The incoming tokens
    private var tokens: [LKToken]

    /// The AST scope tables
    private var scopes: [[LKSyntax]] = [[]]
    /// References to all `define` blocks
    private var defines: Set<String> = []
    /// References to all `inline` blocks
    private var inlines: [(inline: LeafAST.Jump, process: Bool, at: Date)] = []
    private var underestimatedSize: UInt32 = 0

    private var scopeStack = [0]
    private var depth: Int { scopeStack.count - 1 }
    private var currentScope: Int { scopeStack[depth] }
    
    private var scopeDepths: (overallMax: UInt16,
                              inlineMax: UInt16) = (1,0)

    private var openBlocks: [(name: String, block: LeafFunction.Type)] = []
    private var lastBlock: Int? { openBlocks.indices.last }
    
    private var offset: Int = 0

    private var peek: LKToken? { offset < tokens.count ? tokens[offset] : nil }

    private var rawStack: [LKRawBlock]
    
    private var requiredVars: Set<LKVariable> = []
    /// Stack of explicitly created variables and whether they've been set yet
    private var createdVars: [[LKVariable: Bool]] = [[:]]
    
    /// Process the next `LKToken` or multiple tokens.
    private mutating func advance() -> Bool {
        guard let current = pop(), error == nil else { return false }

        /// Get the easy stuff out of the way first...
        guard current == .tagMark else {
            /// 1. Anything that isn't raw is invalid and Lexer shouldn't have produced it
            guard case .raw(var string) = current else { __MajorBug(.malformedToken) }
            /// 2. Aggregate all consecutive raws into one
            while case .raw(let more) = peek { string += more; pop() }
            return appendRaw(string)
        }

        /// 3. Off chance it's tI @ EOF - append a raw tag indicator
        guard peek != nil else { return appendRaw(Character.tagIndicator.description) }

        /// 4. .tagIndicator is *always* followed by .tag - anything else is Lexer error
        guard case .tag(let tag) = pop(), tag != .some("") else { __MajorBug(.malformedToken) }

        /// 5. Everything now is either anonymous, function, or block:
        guard let tagName = tag else {
            /// 5A. Catch anonymous (nil) tags
            guard let tuple = parseTuple(nil), error == nil else { return false }
            if tuple.count > 1 { return bool(err("Anonymous tag can't have multiple parameters")) }
            /// Validate tuple is single parameter, append or evaluate & append raw if invariant
            if var v = tuple[0] {
                if v.resolved && v.invariant { v = .value(v.evaluate([])) }
                guard append(v) else { return false }
            }
            /// Decay trailing colon to raw :
            if peek == .blockMark { appendRaw(":"); offset += 1 }
            return true
        }

        /// 5meta. Handle unique LKMetaBlocks
        if let meta = entities.blockFactories[tagName] as? LKMetaBlock.Type {
            return handleMeta(tagName, meta, parseTuple(tagName)) }
        
        /// See if tag name exists as a block factory, and if so, whether it has parse signatures
        let letRetry: Bool
        if let b = entities.blockFactories[tagName] { letRetry = b.parseSignatures != nil }
        else { letRetry = false }
        /// 5B. Parse the parameter tuple for the tag, if parameters exist, allowing retrying on custom expressions
        let tuple = parseTuple(tagName, retry: letRetry)
        guard error == nil else { return false }

        /// 5C. Catch non-block tags
        guard peek == .blockMark else {
            /// 5D. A normal function call (without a trailing colon)
            if !tagName.hasPrefix("end") && !entities.blockFactories.keys.contains(tagName) {
                return appendFunction(tagName, tuple) }

            /// 5E. A full-stop "end*" tag
            guard let lastBlock = lastBlock else {
                /// 5F. No open blocks on the stack. Failure to close
                return bool(err("No open block to close matching #\(tagName)")) }

            let openTag = tagName.dropFirst(3)
            var canClose = false
            var pass = 0

            /// 5G. Last open block *must* match or it *must* be a chained block
            while lastBlock - pass >= 0 && !canClose {
                let currentBlock = openBlocks[lastBlock - pass]
                /// Match either immediate precedent or head of chain, stop.
                if openTag == currentBlock.name { canClose = true; break }
                /// Not a match. Continue down stack if the current block is an
                /// interstitial chained block (not an opening chainer).
                if let chain = currentBlock.block as? ChainedBlock.Type,
                   !chain.chainsTo.isEmpty { pass += 1 }
                /// Head of chain was not a match, stop.
                else { break }
            }
            /// 5H. No matching open block on the stack. Failure to close.
            guard canClose else { return bool(err("No open block to close matching #\(tagName)")) }
            var isRawBlock = false
            /// Decay chained blocks from the open stack if we were in one.
            for _ in 0...pass { isRawBlock = openBlocks.removeLast().block == RawSwitch.self }
            /// 5I. Successfully (or un) closed block - only one scope will be open, even for chains...
            return closeBlock(isRawBlock)
        }

        /// 5J. Try to make or close/make a block (or decay to function)
        let result = entities.validateBlock(tagName, tuple)

        // TODO: If the call parameters are all literal values evalute
        //       - EG: see/warn if scope is discarded (eg #if(false))

        guard case .success(let block) = result else {
            /// 5K. Any failure to make, short of "not a block", is an error
            if case .failure(let reason) = result,
               !reason.contains("not a block") { return bool(err(reason)) }
            /// 5L. A normal function call with a trailing colon, decay `:` and try to make a normal function
            decayTokenTo(":")
            return appendFunction(tagName, tuple)
        }

        pop() /// Dump scope indicator now

        /// 5M. If new block is chained type, ensure connection and close current scope
        if let chained = type(of: block.0) as? ChainedBlock.Type,
           !chained.chainsTo.isEmpty {
            /// chained interstitial - must be able to close current block
            guard let previous = openBlocks.last?.block as? ChainedBlock.Type,
                  chained.chainsTo.contains(where: {$0 == previous})
            else { return bool(err("No open block for #\(tagName) to close")) }
            guard closeBlock() else { return false }
        }

        /// 5N. Open the new block
        return openBlock(tagName, block.0 as! LeafBlock, block.1)
    }

    @discardableResult
    private mutating func pop() -> LKToken? {
        if let next = peek { offset += 1; return next }; return nil }

    /// Decay the next token up to a specified raw string
    private mutating func decayTokenTo(_ string: String) {
        if peek != nil { tokens[offset] = .raw(string) } }

    /// Append a passthrough syntax object to the current scope and return true to continue parsing
    @discardableResult
    private mutating func append(_ syntax: LKParameter) -> Bool {
        scopes[currentScope].append(.passthrough(syntax))
        underestimatedSize += syntax.underestimatedSize
        
        /// If passthrough object is variable creation, append to current scope's set of created vars
        if case .expression(let e) = syntax.container,
           let declared = e.declaresVariable {
            let v = declared.variable
            /// Check rhs symbols first to avoid checking the declared variable since lower scope may define
            guard updateVars(declared.set?.symbols) else { return false }
            /// Ensure set variable wasn't already declared at this level
            guard checkExplicitVariableState(v, declared.set != nil) else { return false }
            return true
        }
        return updateVars(syntax.symbols)
    }

    /// Append a new raw block from a String.
    @discardableResult
    private mutating func appendRaw(_ raw: String) -> Bool {
        var buffer = ByteBufferAllocator().buffer(capacity: raw.count)
        buffer.writeString(raw)
        underestimatedSize += UInt32(buffer.readableBytes)
        var newRaw = type(of: rawStack.last!).instantiate(data: buffer, encoding: .utf8)
        let checkAt = scopes[currentScope].count - 2
        let blockCheck: Bool
        if checkAt >= 0, case .block = scopes[currentScope][checkAt].container { blockCheck = true }
        else { blockCheck = false }
        // If previous is raw and it's not a scope atomic, concat or append new
        if case .raw(var previous) = scopes[currentScope].last?.container,
           !blockCheck {
            previous.append(&newRaw)
            if let e = previous.error { return bool(err("Serialize Error: \(e)")) }
            scopes[currentScope][checkAt + 1] = .raw(previous)
        } else { scopes[currentScope].append(.raw(buffer)) }
        return true
    }

    /// If the tag name and parameters can create a valid function call, true and append or set error
    private mutating func appendFunction(_ t: String, _ p: LKTuple?) -> Bool {
        let result = entities.validateFunction(t, p)
        underestimatedSize += 16
        guard updateVars(p?.symbols) else { return false }
        switch result {
            case .failure(let r) : return bool(err("\(t) couldn't be parsed: \(r)"))
            case .success(let f)
              where f.count == 1 : return append(.function(t, f[0].0, f[0].1))
            case .success(let f) : return append(.dynamic(t, f, p))
        }
    }

    /// Open a new block scope.
    @discardableResult
    private mutating func openBlock(_ n: String, _ b: LeafBlock, _ p: LKTuple?) -> Bool {
        // New syntaxes in current scope
        scopes[currentScope].append(.block(n, b, p))
        scopes[currentScope].append(.scope(scopes.count))
        openBlocks.append((n, type(of: b))) // Push block onto open stack
        scopes.append([])                   // Create new scope
        scopeStack.append(scopes.count - 1) // Push new scope reference
        scopeDepths.overallMax.maxAssign(UInt16(scopes.count))
        if type(of: b) == Inline.self { scopeDepths.inlineMax.maxAssign(UInt16(scopes.count)) }
        guard updateVars(p?.symbols) else { return false }
        createdVars.append(.init(uniqueKeysWithValues: b.scopeVariables?.map { (.atomic($0), true) } ?? []))
        return true
    }

    /// Close the current scope. If the closing scope is empty or single element, remove its table and inline in place of scope.
    private mutating func closeBlock(_ rawBlock: Bool = false) -> Bool {
        guard currentScope > 0 else { return bool(err("Can't close top scope")) }
        if scopes[currentScope].count < 2 {
            let decayed = scopes.removeLast()
            scopeStack.removeLast()
            guard case .scope = scopes[currentScope].last?.container else {
                __MajorBug("Scope change didn't find a scope reference") }
            scopes[currentScope].removeLast()
            scopes[currentScope].append(decayed.isEmpty ? .scope(nil) : decayed[0] )
        } else { scopeStack.removeLast() }
        if rawBlock { rawStack.removeLast() }
        createdVars.removeLast()
        return true
    }
    
    private mutating func updateVars(_ vars: Set<LKVariable>?) -> Bool {
        guard var x = vars else { return true }
        x = x.reduce(into: [], { $0.insert($1.ancestor)} )
        let scoped = x.filter { $0.isScoped }
        requiredVars.formUnion(scoped)
        x.subtract(scoped)
        
        /// Check that explicit variables referenced are set (or fail)
        for created in createdVars.reversed() {
            let unset = created.filter {$0.value == false}
            let matched = x.intersection(unset.keys)
            if !matched.isEmpty { return bool(err("\(matched.first!) used before assignment")) }
            x.subtract(created.keys)
        }
        
        x.subtract(requiredVars)
        x = x.filter { !requiredVars.contains($0.contextualized) }
        requiredVars.formUnion(x.map {$0.contextualized})
        return true
    }
    
    private mutating func checkExplicitVariableState(_ v: LKVariable, _ set: Bool) -> Bool {
        guard createdVars[depth][v] == nil else { return bool(err("\(v.terse) is already declared in this scope")) }
        createdVars[depth][v] = set
        return true
    }
    
    private mutating func handleEvaluateFunction(_ f: String, _ tuple: LKTuple) -> Evaluate? {
        guard tuple.count == 1, let param = tuple[0] else { return `nil`(err("#\(f) \(Evaluate.warning)")) }
        let identifier: String
        let defaultValue: LKParameter?
        switch param.container {
            case .expression(let e) where e.op == .nilCoalesce:
                guard case .variable(let v) = e.lhs?.container,
                      v.isAtomic, let coalesce = e.rhs, coalesce.isValued
                else { return `nil`(err("#\(f) \(Evaluate.warning)")) }
                identifier = v.member!
                defaultValue = coalesce
            case .variable(let v) where v.isAtomic:
                identifier = String(v.member!)
                defaultValue = nil
            default: return `nil`(err("#\(f) \(Evaluate.warning)"))
        }
        return Evaluate(identifier: identifier, defaultValue: defaultValue)
    }
    
    /// Arbitrate MetaBlocks
    private mutating func handleMeta(_ name: String,
                                     _ meta: LKMetaBlock.Type,
                                     _ tuple: LKTuple?) -> Bool {
        let isBlock: Bool = peek == .blockMark
        if isBlock { pop() }
        switch meta.form {
            case .define:
                guard let tuple = tuple, tuple.count == 2 - (isBlock ? 1 : 0),
                      case .variable(let v) = tuple[0]?.container, v.isAtomic,
                      tuple.count == 2 ? (tuple[1]!.isValued) : true
                else { return bool(err("#\(name) \(Define.warning)")) }
                let definition = Define(identifier: v.member!,
                                        param: !isBlock ? tuple[1]! : nil,
                                        table: currentScope,
                                        row: scopes[currentScope].count + 1)
                if isBlock { openBlock(name, definition, nil) }
                else {
                    scopes[currentScope].append(.block(name, definition, nil))
                    scopes[currentScope].append(.passthrough(definition.param!))
                    guard updateVars(definition.param!.symbols) else { return false }
                }
                defines.insert(v.member!)
            case .evaluate:
                guard let valid = handleEvaluateFunction(name, tuple ?? .init()) else {
                    return false }
                scopes[currentScope].append(.block(name, valid, nil))
                scopes[currentScope].append(valid.defaultValue == nil ? .scope(nil)
                                                : .passthrough(valid.defaultValue!))
                if isBlock { appendRaw(":") }
            case .inline:
                guard let tuple = tuple, (1...2).contains(tuple.count),
                      case .string(let file) = tuple[0]?.data?.container
                else { return bool(err("#\(name) requires a string literal argument for the file")) }
                var process = false
                var raw: String? = nil
                if tuple.count == 2 {
                    guard tuple.labels["as"] == 1, let behavior = tuple[1]?.container
                    else { return bool(err("#\(name)(\"file\", as: type) where type is `leaf` or a raw handler")) }
                    if case .keyword(.leaf) = behavior { process = true }
                    else if case .variable(let v) = behavior, v.isAtomic,
                            let handler = String(v.member!) as String?,
                            handler == "raw" || entities.rawFactories[handler] != nil {
                        raw = handler != "raw" ? handler : nil
                    } else { return bool(err("#\(name)(\"file\", as: type) where type is `leaf`, `raw`, or a named raw handler")) }
                } else { process = true }
                let inline = Inline(file: file,
                                    process: process,
                                    rawIdentifier: process ? nil : raw,
                                    availableVars: createdVars.flat)
                inlines.append((inline: .init(identifier: file,
                                              table: currentScope,
                                              row: scopes[currentScope].count),
                                process: inline.process,
                                at: .distantFuture))
                scopes[currentScope].append(.block(name, inline, nil))
                scopes[currentScope].append(.scope(nil))
                if isBlock { appendRaw(":") }
            case .rawSwitch:
                guard tuple?.isEmpty ?? true else { return bool(err("Using #\(name)() with parameters is not yet supported")) }
                if isBlock {
                    /// When enabled, type will be picked from parameter & params will be passed
                    rawStack.append(type(of: rawStack.last!).instantiate(data: nil, encoding: .utf8))
                    return openBlock(name, RawSwitch(type(of: rawStack.last!), .init()), nil)
                }
        }
        return true
    }

    enum VarState: UInt8, Comparable {
        case start, open, chain
        static func <(lhs: VarState, rhs: VarState) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Try to read parameters. Return nil if no parameters present. Nil for `function` if for expression.
    private mutating func parseTuple(_ function: String?, retry: Bool = false) -> LKTuple? {
        if peek == .paramsStart { pop() } else { return nil }
            
        /// If parsing for a block signature and normal evaluation fails, flag to retry without complex sanity
        /// Set to nil when retrying is not allowed (expressions, functions, no-parse-sig blocks, etc
        var retrying: Bool? = retry ? false : nil
        
        // Parameter parsing stacks
        var functions: [String?] = []
        var tuples: [LKTuple] = []
        var labels: [String?] = []
        var states: [VarState] = []
        var complexes: [[LKParameter]] = []
        
        var variableCreation: (Bool, constant: Bool) = (false, false)
        
        // Conveniences to current stacks
        var currentFunction: String? {
            get { functions.last! }
            set { functions[functions.indices.last!] = newValue}
        }
        var currentTuple: LKTuple {
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
        var currentComplex: [LKParameter] {
            get { complexes.last! }
            set { complexes[complexes.indices.last!] = newValue }
        }
        
        
        // Atomic variable states - doesn't need a stack
        var needIdentifier = false
        var openScope: String? = nil
        var openMember: String? = nil
        var openPath: [String] = []

        /// Current state is for anything but an anonymous (0,1) count expression tuple
        var forFunction: Bool { currentFunction != nil }
        /// Current complex antecedent being valued implies subscripting, unvalued or empty complex implies array
        var subScriptOpensCollection: Bool { !(currentComplex.last?.isValued ?? false) }
        /// If current tuple represents an open collection initializer
        var inCollection: Bool { ["#dictionary", "#array", "#collection"].contains(currentFunction) }
        /// If current state has an open tuple - eg; subscripting opens a complex but not a tuple.
        var inTuple: Bool {
            guard let f = currentFunction else { return false }
            guard f.hasPrefix("#") else { return true }
            return f != "#subscript"
        }

        /// Evaluate the current complex expression into an atomic expression or fail, and close the current complex and label states
        @discardableResult
        func tupleAppend() -> Bool {
            guard currentComplex.count <= 1 else { return bool(err("Couldn't resolve parameter")) }
            defer { currentState = .start; currentLabel = nil; complexes.removeLast(); complexes.append([]) }
            if currentFunction == "#dictionary" {
                if currentComplex.isEmpty { return bool(err("Dictionary literal missing value")) }
                if currentLabel == nil { return bool(err("Dictionary literal missing key")) }
            }
            guard !currentComplex.isEmpty else { return true }
            /// Get the current count of parameters in the current tuple
            guard currentTuple.count != 255 else { return bool(err("Tuples are limited to 256 capacity")) }
            /// Add the parameter to the current tuple's values
            tuples[tuples.indices.last!].values.append(currentComplex[0])
            /// Get the current label if one exists, return if it's nil
            guard let label = currentLabel else { return true }
            /// Ensure the label isn't a duplicate
            if currentTuple.labels.keys.contains(label) { return bool(err("Duplicate entry for \(label)")) }
            /// Add the label to the tuple's labels for the new position
            tuples[tuples.indices.last!].labels[label] = currentTuple.count - 1
            return true
        }

        @discardableResult
        func complexAppend(_ a: LKParameter) -> Bool {
            /// `#(var x), #(var x = value)` - var flags "creation", checked on close complex
            if case .keyword(let k) = a.container, k.isVariableDeclaration {
                guard !forFunction, tuples.count == 1, currentTuple.isEmpty,
                      complexes.allSatisfy({$0.isEmpty}) else {
                    return bool(err("Variable declaration may only occur at start of top level expression")) }
                variableCreation = (true, constant: k == .let)
                return true
            }
            guard makeVariableIfOpen() else { return false }
            if let op = a.operator {
                /// Adding an infix or postfix operator - requires valued antecedent
                if op.infix {
                    guard !currentComplex.isEmpty,
                          currentComplex.last!.isValued else {
                        return bool(err("Can't operate on non-valued parameter")) }
                } else if op.unaryPostfix, !(currentComplex.last?.isValued ?? false) {
                    return bool(err("Missing antecedent value for postfix operator"))
                }
            } else if !currentComplex.isEmpty, retrying != true {
                /// Adding anything else requires the antecedent be a non-unaryPostfix operator
                guard let op = currentComplex.last?.operator, !op.unaryPostfix else {
                    return bool(err("Missing valid operator between parameters")) }
            }
            complexes[complexes.indices.last!].append(a)
            return true
        }

        func complexDrop(_ d: Int) { complexes[complexes.indices.last!].removeLast(d) }

        /// Open a new tuple for a function parameter
        func newTuple(_ function: String? = nil) {
            tuples.append(.init())
            labels.append(nil)
            newComplex(function)
        }

        /// Open a new complex expression
        func newComplex(_ function: String? = nil) {
            functions.append(function)
            states.append(.start)
            complexes.append([])
        }

        func clearVariableState() {
            currentState = .start
            openScope = nil
            openMember = nil
            openPath = []
            needIdentifier = false
        }

        func makeVariableIfOpen() -> Bool {
            guard currentState == .open else { return true }
            let variable = LKVariable(openScope, openMember, openPath.isEmpty ? nil : openPath)
            guard let valid = variable else { return bool(err("Invalid variable identifier")) }
            complexes[complexes.indices.last!].append(.variable(valid))
            clearVariableState()
            return true
        }
        
        func keyValueEntry() -> Bool {
            if currentFunction == "#collection" { currentFunction = "#dictionary" }
            else if currentFunction == "#array" { return bool(err("Can't label elements of an array")) }

            guard case .value(let lD) = currentComplex[0].container,
                  lD.celf == .string, let key = lD.string else {
                return bool(err("Dictionary key must be string literal")) }
            complexDrop(1)
            currentLabel = key
            return true
        }

        /// State should have guaranteed we only call here when tuple is array/dict & non-zero length
        @discardableResult
        func resolveCollection() -> Bool {
            guard closeComplex(), tupleAppend() else { return false }

            let function = functions.removeLast()
            var tuple = tuples.removeLast()
            labels.removeLast()
            complexes.removeLast()
            states.removeLast()
            tuple.collection = true
            
            if function == "#dictionary", tuple.labels.count != tuple.values.count {
                return bool(err("Dictionary initializer missing keys for values")) }
            guard tuple.isEvaluable else { return bool(err("Unevaluable collection initializer")) }
            return complexAppend(.tuple(tuple))
        }

        func resolveSubscript(with identifier: LKParameter? = nil) {
            let parameter: LKParameter?
            if let identifier = identifier {
                guard let object = currentComplex.last, object.isValued else {
                    return void(err("No object to access")) }
                parameter = express([object, .operator(.subScript), identifier])
                complexDrop(1)
            } else {
                guard closeComplex() else { return void(err(.malformedExpression)) }
                states.removeLast()
                guard functions.popLast() == "#subscript",
                      let accessor = complexes.popLast()!.first else {
                    __MajorBug("Invalid subscripting state") }
                guard accessor.isValued, let last = currentComplex.indices.last,
                      last != 0, currentComplex[last].operator == .subOpen else {
                    return void(err("No open subscript to close")) }
                parameter = express([currentComplex[last - 1], .operator(.subScript), accessor])
                complexDrop(2)
            }
            guard let accessed = parameter else { return void(err("Couldn't close subscript")) }
            complexAppend(accessed)
        }

        /// only needed to close ternaryTrue - ternaryFalse won't implicitly open a new complex
        func resolveTernary() {
            guard currentFunction == "#ternary" else { return void(err("Unexpected ternary :")) }
            let whenTrue = complexes.popLast()!.first!
            guard whenTrue.isValued, let last = currentComplex.indices.last,
                  last != 0, currentComplex[last].operator == .ternaryTrue else {
                return void(err("No open ternary to close")) }
            states.removeLast()
            functions.removeLast()
            complexAppend(whenTrue)
        }
        
        func resolveExpression() {
            guard let tuple = tuples.popLast(), tuple.values.count <= 1 else {
                return void(err("Expressions must return a single value")) }
            if tuple.count == 1, let value = tuple.values.first { complexAppend(value) }
        }

        /// Generate a LKExpression, or if an evaluable, invariant expression, a value
        func express(_ params: [LKParameter]) -> LKParameter? {
            if let expression = LKExpression.express(params) {
                return expression.invariant && expression.resolved
                    ? .value(expression.evaluate([]))
                    : .expression(expression)
            } else if let expression = LKExpression.expressTernary(params) {
                return .expression(expression)
            } else if let expression = LKExpression.expressAny(params) {
                return .expression(expression)
            } else { return nil }
        }
        
        /// Branch on a LeafOperator
        func operatorState(_ op: LeafOperator) {
            if [.subOpen, .ternaryTrue].contains(op), !makeVariableIfOpen() { return }
            if [.subClose, .ternaryFalse].contains(op), !closeComplex() { return }

            if op.assigning {
                guard makeVariableIfOpen() else { return }
                guard complexes.count == 1, functions[0] == nil else {
                    return void(err("Assignment only allowed at top level of an expression") )}
                guard case .variable(let assignor) = currentComplex.first?.container,
                      currentComplex.count == 1 else {
                    return void(err("Assignment only allowed as first operation")) }
                if let match = createdVars.match(assignor) {
                    guard !match.0.isConstant || createdVars.last![assignor] == false else {
                        return void(err("Can't assign; \(assignor.flat) is constant")) }
                }
                if op == .assignment && createdVars.last![assignor] == false {
                    createdVars[depth][assignor] = true }
            }

            /// Variable scoping / Method accessor special cases - mutate the open variable state and return
            if op == .scopeRoot {
                guard case .param(.variable(let scope)) = pop(),
                      currentState == .start else { return void(err("Unexpected `$`")) }
                openScope = scope
                currentState = .open
                return
            } else if op == .scopeMember {
                if needIdentifier { return void(err(".. is not meaningful")) }
                if currentState == .start {
                    if currentComplex.last?.isValued == true { currentState = .chain }
                    else { return void(err("Expected identifier")) }
                }
                needIdentifier = true
                return
            }

            switch op {
                case .subOpen where subScriptOpensCollection
                                   : newTuple("#collection")
                case .subOpen      : if case .whiteSpace(_) = tokens[offset - 1] {
                                        return void(err("Subscript may not have leading whitespace")) }
                                     complexAppend(.operator(op))
                                     newComplex("#subscript")
                case .subClose where inCollection
                                   : resolveCollection()
                case .subClose     : resolveSubscript()
                case .ternaryTrue  : complexAppend(.operator(.ternaryTrue))
                                     newComplex("#ternary")
                case .ternaryFalse : resolveTernary()
                                     complexAppend(.operator(.ternaryFalse))
                case .evaluate     : return void(err("\(op) not yet implemented"))
                default            : complexAppend(.operator(op))
            }
        }

        /// Add an atomic variable part to label, scope, member, or part, dependent on state
        func variableState(_ part: String, parseBypass: Bool = false) {
            /// Decay to label identifier if followed by a label indicator
            if peek == .labelMark { currentLabel = part; pop(); return }
            needIdentifier = false
            switch currentState {
                case .start : openMember = part
                              currentState = .open
                case .open where openMember == nil
                            : openMember = part
                case .open  : openPath.append(part)
                case .chain : resolveSubscript(with: .value(.string(part)))
            }
        }

        /// Add a new function to the stack
        func functionState(_ function: String) {
            /// If we were in the middle of a variable, close it. When the next tuple for this function's
            /// parameters close, we'll rewrite the closed variable into the first tuple parameter.
            if currentState == .open { guard makeVariableIfOpen() else { return }
                                       currentState = .chain }
            newTuple(function)
            pop()
        }

        /// Attempt to resolve the current complex expression into an atomic single param (leaving as single value complex)
        func closeComplex() -> Bool {
            // pull the current complex off the stack
            guard makeVariableIfOpen(), var exp = complexes.popLast() else { return false }

            var opCount: Int { countOpsWhere { _ in true } }

            func countOpsWhere(_ check: (LeafOperator) -> Bool) -> Int {
                exp.reduce(0, { $0 + ($1.operator.map {check($0) ? 1 : 0} ?? 0) }) }
            func firstOpWhere(_ check: (LeafOperator) -> Bool) -> Int? {
                for (i, p) in exp.enumerated() {
                    if let op = p.operator, check(op) { return i } }
                return nil }
            func lastOpWhere(_ check: (LeafOperator) -> Bool) -> Int? {
                for (i, p) in exp.enumerated().reversed() {
                    if let op = p.operator, check(op) { return i } }
                return nil }
            func wrapInfix(_ i: Int) -> Bool {
                guard 0 < i && i < exp.count - 1,
                      let wrap = express([exp[i - 1], exp[i], exp[i + 1]]) else { return false }
                exp[i - 1] = wrap; exp.remove(at: i); exp.remove(at: i); return true }
            func wrapNot(_ i: Int) -> Bool {
                guard exp.indices.contains(i + 1),
                      let wrap = express([exp[i], exp[i + 1]]) else { return false }
                exp[i] = wrap; exp.remove(at: i + 1); return true }

            // Wrap single and two op operations first
            if var ops = opCount as Int?, ops != 0 {
                wrapCalculations:
                for map in LeafOperator.evalPrecedenceMap {
                    while let index = lastOpWhere(map.check) {
                        if (map.infixed ? !wrapInfix(index) : !wrapNot(index)) { break wrapCalculations }
                        ops -= 1
                        if opCount == 0 { break wrapCalculations }
                    }
                }
            }

            // Then wrap ternary expressions
            while let tF = firstOpWhere({$0 == .ternaryFalse}) {
                guard tF > 2, exp[tF - 2].operator == .ternaryTrue, exp.count >= tF,
                      let ternary = express([exp[tF - 3], exp[tF - 1], exp[tF + 1]])
                else { return false }
                exp[tF - 3] = ternary; exp.removeSubrange((tF - 2)...(tF + 1))
            }
            
            // Custom expressions can still be at most 3-part, anything more is invalid
            guard exp.count <= 3 else { return false }
            if exp.isEmpty { complexes.append([]); return true }
            guard exp.count > 1 else { exp[0] = exp[0].resolve([]); complexes.append(exp); return true }
            
            // Handle assignment
            if exp[1].operator?.assigning == true {
                if exp.count == 2 { return bool(err("No value to assign")) }
                if !exp[2].isValued { return bool(err("Non-valued type can't be assigned")) }
                exp[2] = exp[2].resolve([])
                complexes.append([.expression(LKExpression.express(exp)!)])
                return true
            }
            
            // Only blocks may have non-atomic parameters, so any complex
            // expression above the first tuple must be atomic - but if we're retrying, bypass
            if tuples.count > 1 || currentFunction == nil, !(retrying ?? false) { return false }
            // Blocks may parse custom expressions so wrap into any expression
            exp = [.expression(LKExpression.expressAny(exp)!)]
            complexes.append(exp)
            return true
        }
        
        /// Hit a `)` - close as appropriate
        func arbitrateClose() {
            guard !(currentFunction?.hasPrefix("#") ?? false) else {
                return void(err("Can't close parameters while in \(currentFunction!)")) }
            /// Try to close the current complex expression, append to the current tuple, and close the current tuple
            let chained = states.count > 1 ? states[states.indices.last! - 1] == .chain : false
            guard closeComplex() else { return error == nil ? void(err("Couldn't close expression")) : () }
            guard tupleAppend() else { return }
            guard tuples.count > 1 || chained else { return }
            let function = functions.removeLast()
            var tuple = tuples.removeLast()
            labels.removeLast()
            complexes.removeLast()
            states.removeLast()
            switch function {
                /// expression
                case .none where retrying == nil:
                    currentComplex.append(tuple.isEmpty ? .value(.trueNil) : tuple.values[0])
                /// tuple where we're in block parsing & top-level
                case .none:
                    currentComplex.append((tuple.isEmpty && tuples.count != 1) ? .value(.trueNil) : .tuple(tuple))
                /// Method function
                case .some(let m) where chained:
                    guard !currentComplex.isEmpty, let operand = currentComplex.popLast(),
                          operand.isValued else { return void(err("Can't call method on non-valued parameter")) }
                    tuple.labels = tuple.labels.mapValues { $0 + 1 }
                    tuple.values.insert(operand, at: 0)
                    var mutable = false
                    if case .variable(let v) = operand.container, !v.isConstant { mutable = true }
                    let result = entities.validateMethod(m, tuple, mutable)
                    switch result {
                        case .failure(let r) : return void(err(r))
                        case .success(let M) :
                            let mutating = (try? result.get().first(where: {($0.0 as! LeafMethod).mutating}) != nil) ?? false
                            var original: LKVariable? = nil
                            if mutating, case .variable(let v) = operand.container {
                                if let match = createdVars.match(v) {
                                    if !match.1 { return void(err("\(v.terse) used before assignment")) }
                                    if match.0.isConstant { return void(err("\(v.terse) is constant; can't call mutating method `\(m)()`")) }
                                }
                                original = v
                            }
                            complexAppend(M.count == 1 ? .function(m, M[0].0, M[0].1, original)
                                                       : .dynamic(m, M, tuple, original))
                    }
                    currentState = .start
                /// Atomic function
                case .some(let f):
                    guard entities.blockFactories[f] as? Evaluate.Type == nil else {
                        if let valid = handleEvaluateFunction(f, tuple) {
                            complexAppend(.function(f, valid, nil)) }
                        break
                    }
                    let result = entities.validateFunction(f, tuple)
                    switch result {
                        case .failure(let r)   : return void(err(r))
                        case .success(let F)
                            where F.count == 1 : complexAppend(.function(f, F[0].0, F[0].1))
                        case .success(let F)   : complexAppend(.dynamic(f, F, tuple))
                    }
            }
        }

        /// open the first complex expression, param label, and tuple, etc.
        newTuple(function)

        // MARK: - Paramter parsing cycle
        parseCycle:
        while error == nil, let next = pop() {
            switch next {
                case .param(let p) :
                    switch p {
                        case .operator(let o) : operatorState(o)
                        case .variable(let v) : variableState(v)
                        case .function(let f) : functionState(f)
                        case .literal(let l)  : complexAppend(.value(l.leafData))
                        case .keyword(let k)
                           where k == .`self` : openScope = LKVariable.selfScope
                                                currentState = .open
                        case .keyword(let k)  : complexAppend(.keyword(k))
                    }
                case .paramDelimit where inTuple || retrying == true
                                   : guard closeComplex() else {
                                         if !errored { void(err(.malformedExpression)) }
                                         break }
                                     tupleAppend()
                case .paramDelimit : void(err("Expressions can't be tuples"))
                case .paramsStart where currentState == .start
                                   : newTuple()
                case .paramsStart  : void(err("Can't use expressions in variable identifier"))
                case .paramsEnd    : arbitrateClose()
                                     if currentComplex.isEmpty { complexes.removeLast() }
                                     if tuples.count == 1 && complexes.isEmpty { break parseCycle }
                case .labelMark    : guard keyValueEntry() else { break }
                case .whiteSpace   : break
                default            : __MajorBug("Lexer produced unexpected \(next) inside parameters")
            }
            // If this is for a block and we errored, retry once
            if error != nil, retry, retrying == false { error = nil; offset -= 1; retrying = true }
        }
        
        /// Error state from grammatically correct but unclosed parameters at EOF
        if !errored && tuples.count > 1 { return `nil`(err("Template ended with open parameters")) }
        if !errored && variableCreation.0 {
            let style = variableCreation.constant ? "let" : "var"
            if tuples[0].count != 1 { return `nil`(err("Declare variables with #(\(style) x) or #(\(style) x = value)")) }
            var theVar: LKVariable? = nil
            var value = tuples[0].values.first!
            switch value.container {
                case .variable(let x) where x.isAtomic: theVar = x; value = .value(.trueNil); break
                case .expression(let e) where e.op == .assignment:
                    guard case .variable(let x) = e.lhs?.container, x.isAtomic else { fallthrough }
                    theVar = x; value = e.rhs!; break
                case .variable: return `nil`(err("Variable declarations may not be pathed"))
                case .expression(let e) where e.form.exp == .assignment:
                    return `nil`(err("Variable assignment at declarations may not be compound expression"))
                default : return `nil`(err("Declare variables with #(\(style) x) or #(\(style) x = value)"))
            }
            if variableCreation.constant { theVar!.state.formUnion(.constant) }
            /// Return a custom expression
            return .init([(nil, .expression(.expressAny([.keyword(variableCreation.constant ? .let : .var), .variable(theVar!), value])!))])
        }
        return !errored ? tuples.popLast() : nil
    }
    
    mutating func bool(_ error: LeafError) -> Bool { self.error = error; return false }
    mutating func void(_ error: LeafError) { self.error = error }
    mutating func `nil`<T>(_ error: LeafError) -> T? { self.error = error; return nil }
}

private extension String {
    static let malformedToken = "Lexer produced malformed tokens"
    static let malformedExpression = "Couldn't close expression"
}

private extension Array where Element == Dictionary<LKVariable, Bool> {
    var flat: Set<LKVariable>? {
        let x = reduce(into: Set<LKVariable>.init(), { $0.formUnion($1.keys) })
        return x.isEmpty ? nil : x
    }
    
    func match(_ v: LKVariable) -> (LKVariable, Bool)? {
        for level in reversed() { if let index = level.index(forKey: v) { return level[index] } }
        return nil
    }
}
