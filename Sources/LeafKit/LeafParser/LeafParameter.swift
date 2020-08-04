// MARK: Subject to change prior to 1.0.0 release
// MARK: -

// FIXME: Can't be internal because of `Syntax`
public indirect enum ParameterDeclaration: SymbolPrintable {
    /// OLD
    case parameter(LeafTokenParameter) // <- CANNOT BE `tag` case
    case expression([ParameterDeclaration])
    case tag(Syntax.CustomTagDeclaration)
    
    public var description: String {
        switch self {
            case .parameter(let p): return p.description
            case .expression(_):    return self.short
            case .tag(let t):       return "function(\(t.name): \(t.params.describe(",")))"
        }
    }

    var short: String {
        switch self {
            case .parameter(let p):  return p.short
            case .expression(let p): return "[\(p.describe())]"
            case .tag(let t):        return "\(t.name)(\(t.params.describe(",")))"
        }
    }

    var name: String {
        switch self {
            case .parameter:  return "parameter"
            case .expression: return "expression"
            case .tag:        return "function"
        }
    }
    
    // MARK: - Internal Only
    
    internal func imports() -> Set<String> {
        switch self {
            case .parameter(_): return .init()
            case .expression(let e): return e.imports()
            case .tag(let t):
                guard t.name == "import" else { return t.imports() }
                guard let parameter = t.params.first,
                      case .parameter(let p) = parameter,
                      case .literal(.string(let key)) = p,
                      !key.isEmpty else { return .init() }
                return .init(arrayLiteral: key)
        }
    }
    
    internal func inlineImports(_ imports: [String : Syntax.Export]) -> ParameterDeclaration {
        switch self {
            case .parameter(_): return self
            case .tag(let t):
                guard t.name == "import" else {
                    return .tag(.init(name: t.name, params: t.params.inlineImports(imports)))
                }
                guard let parameter = t.params.first,
                      case .parameter(let p) = parameter,
                      case .literal(.string(let key)) = p,
                      let export = imports[key]?.body.first,
                      case .expression(let exp) = export,
                      exp.count == 1,
                      let e = exp.first else { return self }
                return e
            case .expression(let e):
                guard !e.isEmpty else { return self }
                return .expression(e.inlineImports(imports))
        }
    }
}

// MARK: - Internal Helper Extensions

internal extension Array where Element == ParameterDeclaration {
    // evaluate a flat array of Parameters ("Expression")
    // returns true if the expression was reduced, false if
    // not or if unreducable (eg, non-flat or no operands).
    // Does not promise that the resulting Expression is valid.
    // This is brute force and not very efficient.
    @discardableResult mutating func nestFlatExpression() -> Bool {
        // Expression with no operands can't be evaluated
        var ops = operandCount()
        guard ops > 0 else { return false }
        
        // Wrap scoping operations - first find any rooted scopes
        while let index = findLastOpWhere( { $0 == .scopeRoot } ) {
            wrapScope(index, rooted: true)
            if ops == operandCount() { return false }
        }
        // Wrap scoping operations - now find any member scopings & wrap methods
        while let index = findLastOpWhere( { $0 == .scopeMember } ) {
            wrapScope(index) // Try to variable name scope
            // previous won't wrap if lhs is tag - try that next
            if ops == operandCount() { wrapMethod(index) }
            // At this point it's invalid
            if ops == operandCount() { return false }
        }
        // Wrap scoping operations - now wrap subscripts
        while let index = findLastOpWhere( { $0 == .subOpen } ) {
            wrapSubscript(index)
            if ops == operandCount() { return false }
        }
        
        // Next wrap evaluation operations
        groupEval: for map in LeafOperator.evalPrecedenceMap {
            while let index = findLastOpWhere(map.check) {
                if map.infixed { wrapBinaryOp(index) }
                else { wrapUnaryNot(index) }
                // Some expression could not be wrapped - probably malformed syntax
                if ops == operandCount() { return false } else { ops -= 1 }
                if operandCount() == 0 { break groupEval }
            }
        }

        flatten()
        return ops > 1 ? true : false
    }
    
    // Wrap subscript access
    private mutating func wrapSubscript(_ i: Int) {
        // must not be first param & at least 2 rhs; +2 must be subClose
        guard i > 0, indices.contains(i + 2),
              self[i+2].operator == .subClose else { return }
        // If it's a parameter ensure it's only a 0+ Int or a non-empty String
        if case .parameter(let p) = self[i+1] {
            switch p {
                case .literal(let c):
                    if case .double(_) = c { return }
                    if case .int(let i) = c, i < 0 { return }
                    if case .string(let s) = c, s.isEmpty { return }
                case .variable(_): break
                default: return
            }
        }
        self[i-1] = .expression([self[i-1], .parameter(.operator(.subScript)), self[i+1]])
        removeSubrange(i...i+2)
    }
    
    
    // Wrap a method chain - both sides must be tags
    private mutating func wrapMethod(_ i: Int) {
        guard indices.contains(i - 1), indices.contains(i + 1),
              case .tag(let lhs) = self[i-1],
              case .tag(let rhs) = self[i+1] else { return }
        self[i-1] = .tag(.init(name: rhs.name,
                               params: [.tag(lhs)] + rhs.params))
        removeSubrange(i...i+1)
    }
    
    
    /// Wrap any variable references
    private mutating func wrapScope(_ i: Int, rooted: Bool = false) {
        let replace = rooted ? i : i - 1
        let removeStart = replace + 1
        var scope: String // ($|$namedScope)[.member]*
        var remove = 0
        if rooted {
            if i != 0 { // If not at the front, precedent must be any nonscoping or subopen
                let lhs = self[i-1]
                guard case .parameter(let p) = lhs, case .operator(let op) = p,
                      !op.scoping || op == .subOpen else { return }
            }  // Rooted scope needs min 2 rhs, get the first rhs
            guard indices.contains(i+2),
                  case .parameter(let p) = self[i+1] else { return }
            if case .variable(let v) = p, let op = self[i+2].operator, op == .scopeMember {
                scope = "$\(v)"; remove += 1 }
            else if case .operator(let op) = p, op == .scopeMember { scope = "$" }
            else { return } // Invalid scope root - can't flatten
        } else {
            guard i != 0 else { return } // . can't open expression. If Lhs
            scope = ""
        }
        
        // starting *member* index
        var index = i + (!rooted ? 1 : 2 + remove)
        // Scope while next tokens are "member", "."
        while indices.contains(index) && indices.contains(index + 1),
              case .parameter(let p) = self[index], case .variable(let v) = p,
              self[index + 1].operator == .scopeMember {
            scope += ".\(v)"
            remove += 2
            index += 2
        }
        // If we haven't advanced or no more tokens (eg ended on "."), invalid
        //
        guard index > (i + remove), indices.contains(index) else { return }
        
        // Now get the last element, which could be a member or a tag
        switch (rooted, self[index]) {
            case (_,    .expression(_)): return // Expression can't be member (until eval)
            case (true, .parameter(let p)): // Ending on member
                guard case .variable(let v) = p else { return }
                scope += ".\(v)"                 // Fully scoped variable
                self[replace] = .parameter(.variable(scope))
            case (true, .tag(let t)):       // Ending on tag
                self[replace] =
                    .tag(.init(name: t.name,      // Re-wrap tag with new first param
                               params: [.parameter(.variable(scope))] + t.params))
            case (false, .parameter(let p)): // ending on member, grab the original
                if case .parameter(.variable(let first)) = self[replace] {
                    // lhs is variable name
                    guard case .variable(let v) = p else { return }
                    scope += ".\(v)"
                    self[replace] = .parameter(.variable("$.\(first)\(scope)"))
                } else { // lhs is not a variable id - subscript instead
                    self[replace] = .expression([
                                        self[replace],
                                        .parameter(.operator(.subScript)),
                                        .parameter(.variable("$\(scope)"))])
                }
            case (false, .tag(let t)):      // ending on tag, grab the original
                if case .parameter(.variable(let v)) = self[replace] {
                    self[replace] =  .tag(.init(name: t.name,  // Re-wrap tag
                                   params: [.parameter(.variable("$.\(v).\(scope)"))] + t.params))
                } else { // lhs is not a variable id - subscript instead
                    self[replace] = .tag(.init(
                        name: t.name,
                        params: [.expression([
                                    self[replace],
                                    .parameter(.operator(.subScript)),
                                    .parameter(.variable(scope))
                                ])] + t.params))
                }
                
        }
        removeSubrange(removeStart...(removeStart + remove + 1))
    }

    mutating func flatten() {
        while count == 1 {
            if case .expression(let e) = self.first! {
                self.removeAll()
                self.append(contentsOf: e)
            } else { return }
        }
        return
    }

    private mutating func wrapUnaryNot(_ i: Int) {
        let rhs = remove(at: i + 1)
        if case .parameter(let p) = rhs, case .keyword(let key) = p, key.isBooleanValued {
            self[i] = .parameter(.keyword(LeafKeyword(rawValue: String(!key.bool!))!))
        } else {
            self[i] = .expression([self[i],rhs])
        }
    }

    // could be smarter and check param types beyond verifying non-op but we're lazy here
    private mutating func wrapBinaryOp(_ i: Int) {
        // can't wrap unless there's a lhs and rhs
        guard self.indices.contains(i-1),self.indices.contains(i+1) else { return }
        let lhs = self[i-1]
        let rhs = self[i+1]
        // can't wrap if lhs or rhs is an operator
        if case .parameter(.operator) = lhs { return }
        if case .parameter(.operator) = rhs { return }
        self[i] = .expression([lhs, self[i], rhs])
        self.remove(at:i+1)
        self.remove(at:i-1)
    }

    // Helper functions
    func operandCount() -> Int { return reduceOpWhere { _ in true } }
    func binaryOps() -> Int { return reduceOpWhere { $0.infix } }
    func reduceOpWhere(_ check: (LeafOperator) -> Bool) -> Int {
        return self.reduce(0, { count, pD  in
            return count + (pD.operator.map { check($0) ? 1 : 0 } ?? 0)
        })
    }

    func findLastOpWhere(_ check: (LeafOperator) -> Bool) -> Int? {
        for (index, pD) in self.enumerated().reversed() {
            if let op = pD.operator, check(op) { return index }
        }
        return nil
    }
    
    func describe(_ joinBy: String = " ") -> String {
        self.map {$0.short }.joined(separator: joinBy)
    }
    
    func imports() -> Set<String> {
        var result = Set<String>()
        self.forEach { result.formUnion($0.imports()) }
        return result
    }
    
    func inlineImports(_ imports: [String : Syntax.Export]) -> [ParameterDeclaration] {
        guard !isEmpty else { return self }
        guard !imports.isEmpty else { return self }
        return self.map { $0.inlineImports(imports) }
    }
    
    func atomicRaw() -> Syntax? {
        // only atomic expressions can be converted
        guard self.count < 2 else { return nil }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        // empty expressions = empty raw
        guard self.count == 1 else { return .raw(buffer) }
        // only single value parameters can be converted
        guard case .parameter(let p) = self[0] else { return nil }
        switch p {
            case .literal(.string(let s)): buffer.writeString(s)
            case .literal(let c): buffer.writeString(c.description)
            case .keyword(let k): buffer.writeString(k.rawValue)
            case .operator(let o): buffer.writeString(o.rawValue)
            // .tag, .variable not atomic
            default: return nil
        }
        return .raw(buffer)
    }
}
