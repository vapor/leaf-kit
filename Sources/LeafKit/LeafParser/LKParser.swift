// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation
import NIO

internal struct LKParser {
    // MARK: - Internal Only

    let key: LeafASTKey

    init(_ key: LeafASTKey, _ tokens: [LKToken]) {
        self.entities = LKConf.entities
        self.key = key
        self.tokens = tokens
        self.rawStack = [entities.raw.instantiate(data: nil, encoding: .utf8)]
        self.emptyVariables = .allocate(capacity: 1)
        self.emptyVariables.initialize(to: [:])
    }

    mutating func parse() throws -> LeafAST {
        var more = true
        while more { more = advance() }
        if error == nil, !openBlocks.isEmpty {
            voidErr("[\(openBlocks.map { "#\($0.name)(...):" }.joined(separator: ", "))] still open at EOF")
        }
        emptyVariables.deinitialize(count: 1)
        emptyVariables.deallocate()
        if let error = error { throw error }
        return LeafAST(key,
                       scopes,
                       defines,
                       inlines,
                       underestimatedSize,
                       scopeDepths)
    }

    // MARK: - Private Only
    /// The active entities reference object
    private var entities: LeafEntities
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
    private var currentScope: Int { scopeStack.last! }
    private var scopeDepths: (overallMax: UInt16,
                              inlineMax: UInt16) = (1,0)

    private var openBlocks: [(name: String, block: LeafFunction.Type)] = []
    private var lastBlock: Int? { openBlocks.indices.last }

    private var offset: Int = 0
    private var error: LeafError? = nil { willSet {  } }

    private var peek: LKToken? { offset < tokens.count ? tokens[offset] : nil }

    private var rawStack: [RawBlock]
    
    private var emptyVariables: LKVarTablePointer

        /// Process the next `LKToken` or multiple tokens.
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
                return boolErr("Anonymous tag can't have multiple parameters") }
            if let tuple = tuple, let value = tuple[0] {
                guard case .value(let data) = value.container,
                      data.resolved && data.invariant else { append(value); return true }
                appendRaw(data)
            }
            return true
        }

        if let meta = entities.blockFactories[tagName] as? LKMetaBlock.Type {
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
                return boolErr("No open block to close matching #\(tagName)")
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
            guard canClose else { return boolErr("No open block to close matching #\(tagName)") }
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
               !reason.contains("not a block") { return boolErr(reason) }
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
            else { return boolErr("No open block for #\(tagName) to close") }
            guard closeBlock() else { return false }
        }

        // 5N. Open the new block
        return openBlock(tagName, block.0 as! LeafBlock, block.1)
    }

    @discardableResult
    private mutating func pop() -> LKToken? {
        if let next = peek { offset += 1; return next }; return nil
    }

    /// Decay the next token up to a specified raw string
    private mutating func decayTokenTo(_ string: String) {
        if peek != nil { tokens[offset] = .raw(string) }
    }

    /// Append a passthrough syntax object to the current scope and return true to continue parsing
    @discardableResult
    private mutating func append(_ syntax: LKParameter) -> Bool {
        scopes[currentScope].append(.passthrough(syntax))
        let estimate: UInt32
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
        underestimatedSize += UInt32(buffer.readableBytes)
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
    private mutating func appendRaw(_ data: LKData) -> Bool {
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
    private mutating func appendFunction(_ t: String, _ p: LKTuple?) -> Bool {
        let result = entities.validateFunction(t, p)
        underestimatedSize += 16
        switch result {
            case .failure(let r): return boolErr("\(t) couldn't be parsed: \(r)")
            case .success(let f): return append(.function(t, f.0, f.1))
        }
    }

    /// Open a new block scope.
    private mutating
    func openBlock(_ n: String, _ b: LeafBlock, _ p: LKTuple?) -> Bool {
        // New syntaxes in current scope
        scopes[currentScope].append(.block(n, b, p))
        scopes[currentScope].append(.scope(scopes.count))
        openBlocks.append((n, type(of: b))) // Push block onto open stack
        scopes.append([])                   // Create new scope
        scopeStack.append(scopes.count - 1) // Push new scope reference
        scopeDepths.overallMax.maxAssign(UInt16(scopes.count))
        if type(of: b) == Inline.self { scopeDepths.inlineMax.maxAssign(UInt16(scopes.count)) }
        return true
    }

    /// Close the current scope. If the closing scope is empty or single element, remove its table and inline in place of scope.
    private mutating func closeBlock(_ rawBlock: Bool = false) -> Bool {
        guard currentScope > 0 else { return boolErr("Can't close top scope") }
        if scopes[currentScope].count < 2 {
            let decayed = scopes.removeLast()
            scopeStack.removeLast()
            guard case .scope = scopes[currentScope].last?.container else {
                __MajorBug("Scope change didn't find a scope reference")
            }
            scopes[currentScope].removeLast()
            scopes[currentScope].append(decayed.isEmpty ? .scope(nil) : decayed[0] )
        } else { scopeStack.removeLast() }
        if rawBlock { rawStack.removeLast() }
        return true
    }

    private mutating func handleMeta(_ name: String,
                                     _ meta: LKMetaBlock.Type,
                                     _ tuple: LKTuple?) -> Bool {
        let isBlock: Bool = peek == .scopeIndicator
        if isBlock { pop() }
        switch meta.form {
            case .define:
                guard let tuple = tuple, tuple.count == 2 - (isBlock ? 1 : 0),
                      case .variable(let v) = tuple[0]?.container, v.atomic,
                      tuple.count == 2 ? (tuple[1]!.isValued) : true
                else { return boolErr("#\(name) \(Define.warning)") }
                let definition = Define(identifier: v.member!,
                                        table: currentScope,
                                        row: scopes[currentScope].count + 1)
                if isBlock { _ = openBlock(name, definition, tuple) }
                else {
                    let value = tuple[1]!
                    scopes[currentScope].append(.block(name, definition, tuple))
                    scopes[currentScope].append(.passthrough(value))
                }
                defines.insert(v.member!)
            case .evaluate:
                guard let tuple = tuple, tuple.count == 1, let param = tuple[0] else {
                    return boolErr("#\(name) \(Evaluate.warning)") }
                let definedName: String
                let defaultValue: LKParameter?
                switch param.container {
                    case .expression(let e) where e.op == .nilCoalesce:
                        guard case .variable(let v) = e.lhs?.container,
                              v.atomic, let coalesce = e.rhs, coalesce.isValued
                        else { return boolErr("#\(name) \(Evaluate.warning)") }
                        definedName = v.member!
                        defaultValue = coalesce
                    case .variable(let v) where v.atomic:
                        definedName = String(v.member!)
                        defaultValue = nil
                    default: return boolErr("#\(name) \(Evaluate.warning)")
                }
                scopes[currentScope].append(.block(name, Evaluate(identifier: definedName), tuple))
                scopes[currentScope].append(defaultValue == nil ? .scope(nil)
                                                : .passthrough(defaultValue!))
                if isBlock { appendRaw(Character.tagIndicator.description) }
            case .inline:
                guard let tuple = tuple, (1...2).contains(tuple.count),
                      case .string(let file) = tuple[0]?.data?.container
                else { return boolErr("#\(name) requires a string literal argument for the file") }
                var process = false
                var raw: String? = nil
                if tuple.count == 2 {
                    guard tuple.labels["as"] == 1, let behavior = tuple[1]?.container
                    else { return boolErr("#\(name)(\"file\", as: type) where type is `leaf` or a raw handler") }
                    if case .keyword(.leaf) = behavior { process = true }
                    else if case .variable(let v) = behavior, v.atomic,
                            let handler = String(v.member!) as String?,
                            handler == "raw" || entities.rawFactories[handler] != nil {
                        raw = handler != "raw" ? handler : nil
                    } else { return boolErr("#\(name)(\"file\", as: type) where type is `leaf`, `raw`, or a named raw handler") }
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
                guard tuple?.isEmpty ?? true else { return boolErr("Using #\(name)() with parameters is not yet supported") }
                if isBlock {
                    // When enabled, type will be picked from parameter & params will be passed
                    rawStack.append(type(of: rawStack.last!).instantiate(data: nil, encoding: .utf8))
                    return openBlock(name, RawSwitch(type(of: rawStack.last!), .init()), tuple)
                }
                else { appendRaw("") }
        }
        return true
    }

    enum VarState: UInt8, Comparable {
        case start, open, chain
        static func <(lhs: VarState, rhs: VarState) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Try to read parameters. Return nil if no parameters present. Nil for `function` if for expression.
    private mutating func parseTuple(_ function: String?, forParse: Bool = false) -> LKTuple? {
        if peek == .parametersStart { pop() } else { return nil }

        // Stacks
        var functions: [String?] = []
        var tuples: [LKTuple] = []
        var labels: [String?] = []
        var states: [VarState] = []
        var complexes: [[LKParameter]] = []

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
        var atomicComplex: LKParameter? {
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
                return boolErr("Couldn't resolve parameter") }
            defer { currentState = .start; currentLabel = nil;
                    complexes.removeLast(); complexes.append([]) }
            if currentFunction == "#dictionary" {
                if currentComplex.isEmpty { return boolErr("Dictionary literal missing value") }
                if currentLabel == nil { return boolErr("Dictionary literal is missing key") }
            }
            guard !currentComplex.isEmpty else { return true }
            // Get the current count of parameters in the current tuple
            guard currentTuple.count != 255 else { return boolErr("Tuples are limited to 256 capacity") }
            // Add the parameter to the current tuple's values
            tuples[tuples.indices.last!].values.append(atomicComplex!)
            // Get the current label if one exists, return if it's nil
            guard let label = currentLabel else { return true }
            // Ensure the label isn't a duplicate
            if currentTuple.labels.keys.contains(label) { return boolErr("Duplicate entry for \(label)") }
            // Add the label to the tuple's labels for the new position
            tuples[tuples.indices.last!].labels[label] = currentTuple.count - 1
            return true
        }

        @discardableResult
        func complexAppend(_ a: LKParameter, sanity: Bool = true) -> Bool {
            if sanity {
                guard makeVariableIfOpen() else { return false }
                /// Adding an infix operator - requires valued antecedent
                if let op = a.operator {
                    if op.infix {
                        guard !currentComplex.isEmpty,
                              currentComplex.last!.isValued else {
                            return boolErr("Can't operate on non-valued parameter") }
                    } else if op.unaryPostfix, !(currentComplex.last?.isValued ?? false) {
                        return boolErr("Missing antecedent value for postfix operator")
                    }
                /// Adding anything else requires the antecedent be a non-unaryPostfix operator
                } else if !currentComplex.isEmpty, retrying != true {
                    guard let op = currentComplex.last?.operator, !op.unaryPostfix
                        else {
                        return boolErr("Missing valid operator between parameters")

                    }
                }
            } else { clearVariableState() }
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
            openMember = ""
            openPath = []
            needIdentifier = false
        }

        func makeVariableIfOpen() -> Bool {
            guard currentState == .open else { return true }
            let variable = LKVariable(openScope, openMember, openPath.isEmpty ? nil : openPath)
            guard let valid = variable else { return boolErr("Invalid variable identifier") }
            complexes[complexes.indices.last!].append(.variable(valid))
            clearVariableState()
            return true
        }

        /// Current complex antecedent being valued implies subscripting, unvalued or empty complex implies array
        var subScriptOpensCollection: Bool { !(currentComplex.last?.isValued ?? false) }

        var inCollection: Bool { ["#dictionary", "#array", "#collection"].contains(currentFunction) }

        func keyValueEntry() -> Bool {
            if currentFunction == "#collection" { currentFunction = "#dictionary" }
            else if currentFunction == "#array" { return boolErr("Can't label elements of an array") }

            guard case .value(let lD) = currentComplex[0].container,
                  lD.celf == .string, let key = lD.string else {
                return boolErr("Dictionary key must be string literal") }
            complexDrop(1)
            currentLabel = key
            return true
        }

        /// State should have guaranteed we only call here when tuple is array/dict & non-zero length &
        @discardableResult
        func resolveCollection() -> Bool {
            guard closeComplex() else { return false }
            guard tupleAppend() else { return false }

            let function = functions.removeLast()
            let tuple = tuples.removeLast()
            labels.removeLast()
            complexes.removeLast()
            states.removeLast()
            
            if function == "#dictionary", tuple.labels.count != tuple.values.count {
                return boolErr("Dictionary initializer missing keys for values") }
            guard tuple.isEvaluable else { return boolErr("Unevaluable collection initializer") }
            return complexAppend(.tuple(tuple))
        }

        func resolveSubscript(with identifier: LKParameter? = nil) {
            let parameter: LKParameter?
            if let identifier = identifier {
                guard let object = currentComplex.last, object.isValued else {
                    return voidErr("No object to access") }
                parameter = express([object, .operator(.subScript), identifier])
                complexDrop(1)
            } else {
                guard closeComplex() else { return voidErr("Couldn't close expression") }
                states.removeLast()
                guard functions.popLast() == "#subscript",
                      let accessor = complexes.popLast()!.first else {
                    __MajorBug("Invalid subscripting state") }
                guard accessor.isValued, let last = currentComplex.indices.last,
                      last != 0, currentComplex[last].operator == .subOpen else {
                    return voidErr("No open subscript to close") }
                parameter = express([currentComplex[last - 1], .operator(.subScript), accessor])
                complexDrop(2)
            }
            guard let accessed = parameter else { return voidErr("Couldn't close subscript") }
            complexAppend(accessed, sanity: false)
        }

        /// only needed to close ternaryTrue - ternaryFalse won't implicitly open a new complex
        func resolveTernary() {
            guard currentFunction == "#ternary" else { return voidErr("Unexpected ternary :") }
            let whenTrue = complexes.popLast()!.first!
            guard whenTrue.isValued, let last = currentComplex.indices.last,
                  last != 0, currentComplex[last].operator == .ternaryTrue else {
                return voidErr("No open ternary to close") }
            states.removeLast()
            functions.removeLast()
            complexAppend(whenTrue)
        }

        /// Generate a LKExpression, or if an evaluable, invariant expression, a value
        func express(_ params: [LKParameter]) -> LKParameter? {
            if let expression = LKExpression.express(params) {
                return expression.invariant && expression.resolved
                    ? .value(expression.evaluate(emptyVariables)) : .expression(expression)
            } else if let expression = LKExpression.expressTernary(params) {
                return .expression(expression)
            } else if let expression = LKExpression.expressAny(params) {
                return .expression(expression)
            } else { return nil }
        }

        func operatorState(_ op: LeafOperator) {
            if [.subOpen, .ternaryTrue].contains(op), !makeVariableIfOpen() { return }
            if [.subClose, .ternaryFalse].contains(op), !closeComplex() { return }

            if op.assigning {
                guard makeVariableIfOpen() else { return }
                guard complexes.count == 1, functions[0] == nil else {
                    return voidErr("Assignment only allowed at top level of an expression") }
                guard case .variable(let assignor) = currentComplex.first?.container,
                      currentComplex.count == 1 else {
                    return voidErr("Assignment only allowed as first operation") }
                guard assignor.scope == nil else {
                    return voidErr("Can't assign; \(assignor.flat) is constant") }
            }

            /// Variable scoping / Method accessor special cases - mutate the open variable state and return
            if op == .scopeRoot {
                guard case .parameter(.variable(let scope)) = pop(),
                      currentState == .start else { return voidErr("Unexpected `$`") }
                openScope = scope
                currentState = .open
                return
            } else if op == .scopeMember {
                if needIdentifier { return voidErr(".. is not meaningful") }
                if currentState == .start {
                    if currentComplex.last?.isValued == true { currentState = .chain }
                    else { return voidErr("Expected identifier") }
                }
                needIdentifier = true
                return
            }

            switch op {
                case .subOpen where subScriptOpensCollection
                                   : newTuple("#collection")
                case .subOpen      : if case .whiteSpace(_) = tokens[offset - 1] {
                                        return voidErr("Subscript may not have leading whitespace") }
                                     complexAppend(.operator(op))
                                     newComplex("#subscript")
                case .subClose where inCollection
                                   : resolveCollection()
                case .subClose     : resolveSubscript()
                case .ternaryTrue  : complexAppend(.operator(.ternaryTrue))
                                     newComplex("#ternary")
                case .ternaryFalse : resolveTernary()
                                     complexAppend(.operator(.ternaryFalse))
                case .evaluate     : return voidErr("\(op) not yet implemented")
                default            : complexAppend(.operator(op))
            }
        }

        /// Add an atomic variable part to label, scope, member, or part,, dependent on state
        func variableState(_ part: String, parseBypass: Bool = false) {
            /// Decay to label identifier if followed by a label indicator
            if peek == .labelIndicator { currentLabel = part; pop(); return }
            needIdentifier = false
            switch currentState {
                case .start : openMember = part
                              currentState = .open
                case .open where openMember == ""
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

        var inTuple: Bool {
            guard let f = currentFunction else { return false }
            guard f.hasPrefix("#") else { return true }
            return f != "#subscript"
        }

        /// Attempt to resolve the current complex expression
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
            guard exp.count > 1 else { complexes.append(exp)
                                       return true }
            
            // Handle assignment
            if exp[1].operator?.assigning == true {
                if exp.count == 2 { return boolErr("No value to assign") }
                if !exp[2].isValued { return boolErr("Non-valued type can't be assigned") }
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

        func arbitrateClose() {
            guard !(currentFunction?.hasPrefix("#") ?? false) else {
                return voidErr("Can't close parameters while in \(currentFunction!)") }
            // Try to close the current complex expression, append to the current tuple,
            // and close the current tuple
            let chained = states.count > 1 ? states[states.indices.last! - 1] == .chain : false
            guard closeComplex() else { return error == nil ? voidErr("Couldn't close expression") : () }
            guard tupleAppend() else { return }
            guard tuples.count > 1 || chained else { return }
            let function = functions.removeLast()
            var tuple = tuples.removeLast()
            labels.removeLast()
            complexes.removeLast()
            states.removeLast()
            switch function {
                // expression
                case .none where retrying == nil:
                    currentComplex.append(tuple.isEmpty ? .value(.trueNil) : tuple.values[0])
                // tuple where we're in block parsing & top-level
                case .none:
                    currentComplex.append((tuple.isEmpty && tuples.count != 1) ? .value(.trueNil) : .tuple(tuple))

                // Method function
                case .some(let m) where chained:
                    guard !currentComplex.isEmpty, let operand = currentComplex.popLast(),
                          operand.isValued else { voidErr("Can't call method on non-valued parameter"); break }
                    tuple.labels = tuple.labels.mapValues { $0 + 1 }
                    tuple.values.insert(operand, at: 0)
                    let result = entities.validateMethod(m, tuple)
                    switch result {
                        case .failure(let r): return voidErr("\(m) couldn't be parsed: \(r)")
                        case .success(let M): complexAppend(.function(m, M.0, M.1))
                    }
                    currentState = .start
                // Atomic function
                case .some(let f):
                    let result = entities.validateFunction(f, tuple)
                    switch result {
                        case .failure(let r): return voidErr("\(f) couldn't be parsed: \(r)")
                        case .success(let F): complexAppend(.function(f, F.0, F.1))
                    }
            }

        }

        // Atomic states
        var needIdentifier = false
        var openScope: String? = nil
        var openMember: String = ""
        var openPath: [String] = []

        // open the first complex expression, param label, and tuple
        newTuple(function)

        func resolveExpression() {
            guard let tuple = tuples.popLast(), tuple.values.count <= 1 else {
                return voidErr("Expressions must return a single value") }
            if tuple.count == 1, let value = tuple.values.first { complexAppend(value) }
        }

        parseCycle:
        while error == nil, let next = pop() {
            switch next {
                case .whiteSpace           : break
                case .parameter(let param) :
                    switch param {
                        case .operator(let o) : operatorState(o)
                        case .variable(let v) : variableState(v)
                        case .function(let f) : functionState(f)
                        case .literal(let l)  : complexAppend(.value(l.leafData))
                        case .keyword(let k) where k == .`self`
                                              : openScope = LKVariable.selfScope
                                                currentState = .open
                        case .keyword(let k)  : complexAppend(.keyword(k))
                    }
                case .parameterDelimiter where inTuple || retrying == true
                                           : guard closeComplex() else {
                                                if error == nil { voidErr("Couldn't close expression") }
                                                break }
                                             tupleAppend()
                case .parameterDelimiter   : voidErr("Expressions can't be tuples")
                case .parametersStart where currentState == .start
                                           : newTuple()
                case .parametersStart      : voidErr("Can't use expressions in variable identifier")
                case .parametersEnd        : arbitrateClose()
                                             if currentComplex.isEmpty { complexes.removeLast() }
                                             if tuples.count == 1 && complexes.isEmpty { break parseCycle }
                case .labelIndicator       : guard keyValueEntry() else { break }
                default                    : __MajorBug("Lexer produced unexpected \(next) inside parameters")
            }
            // If this is for a block and we errored, retry once
            if error != nil, forParse, retrying == false { error = nil; offset -= 1; retrying = true }
        }

        // Error states from parameter parsing
        if error != nil { return nil }
        // Error state from grammatically correct but unclosed parameters at EOF
        if tuples.count != 1 { voidErr("Template ended with open parameters") }
        return tuples.count == 1 ? tuples.popLast() : nil
    }

    /// Set parsing error state and return false to halt parsing
    private mutating func boolErr(_ reason: String,
                                  file: String = #file,
                                  function: String = #function,
                                  line: UInt = #line,
                                  column: UInt = #column) -> Bool {
        error = LeafError(.unknownError(reason),
                          file: String(file.split(separator: "/").last ?? ""),
                          function: function, line: line, column: column)
        return false
    }

    private mutating func voidErr(_ reason: String,
                                  file: String = #file,
                                  function: String = #function,
                                  line: UInt = #line,
                                  column: UInt = #column) {
        error = LeafError(.unknownError(reason),
                          file: String(file.split(separator: "/").last ?? ""),
                          function: function, line: line, column: column)
    }
}

private extension String {
    static let malformedToken = "Lexer produced malformed tokens"
}
