import NIO

public indirect enum ParameterDeclaration: CustomStringConvertible, Sendable {
    case parameter(Parameter)
    case expression([ParameterDeclaration])
    case tag(Syntax.CustomTagDeclaration)

    public var description: String {
        switch self {
            case .parameter(let p): return p.description
            case .expression(_):    return self.short
            case .tag(let t):       return "tag(\(t.name): \(t.params.describe(",")))"
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
            case .tag:        return "tag"
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
                      case .stringLiteral(let key) = p,
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
                      case .stringLiteral(let key) = p,
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
    @discardableResult mutating func evaluate() -> Bool {
        // Expression with no operands can't be evaluated
        var ops = operandCount()
        guard ops > 0 else { return false }
        // check that the last param isn't an op, this is not resolvable
        // since there are no unary postfix options currently
        guard last?.operator() == nil else { return false }

        groupOps: for map in LeafOperator.precedenceMap {
            while let i = findLastOpWhere(map.check) {
                if map.infixed { wrapBinaryOp(i) }
                else { wrapUnaryNot(i) }
                // Some expression could not be wrapped - probably malformed syntax
                if ops == operandCount() { return false } else { ops -= 1 }
                if operandCount() == 0 { break groupOps }
            }
        }

        flatten()
        return ops > 1 ? true : false
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

    fileprivate mutating func wrapUnaryNot(_ i: Int) {
        let rhs = remove(at: i + 1)
        if case .parameter(let p) = rhs, case .keyword(let key) = p, key.isBooleanValued {
            self[i] = .parameter(.keyword(LeafKeyword(rawValue: String(!key.bool!))!))
        } else {
            self[i] = .expression([self[i],rhs])
        }
    }

    // could be smarter and check param types beyond verifying non-op but we're lazy here
    fileprivate mutating func wrapBinaryOp(_ i: Int) {
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
    func unaryOps() -> Int { return reduceOpWhere { $0.unaryPrefix } }
    func binaryOps() -> Int { return reduceOpWhere { $0.infix } }
    func reduceOpWhere(_ check: (LeafOperator) -> Bool) -> Int {
        return self.reduce(0, { count, pD  in
            return count + (pD.operator().map { check($0) ? 1 : 0 } ?? 0)
        })
    }

    func findLastOpWhere(_ check: (LeafOperator) -> Bool) -> Int? {
        for (index, pD) in self.enumerated().reversed() {
            if let op = pD.operator(), check(op) { return index }
        }
        return nil
    }
    
    func describe(_ joinBy: String = " ") -> String {
        return self.map {$0.short }.joined(separator: joinBy)
    }
    
    func imports() -> Set<String> {
        var result = Set<String>()
        self.forEach { result.formUnion($0.imports()) }
        return result
    }
    
    func inlineImports(_ imports: [String : Syntax.Export]) -> [ParameterDeclaration] {
        guard !self.isEmpty else { return self }
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
            case .constant(let c): buffer.writeString(c.description)
            case .keyword(let k): buffer.writeString(k.rawValue)
            case .operator(let o): buffer.writeString(o.rawValue)
            case .stringLiteral(let s): buffer.writeString(s)
            // .tag, .variable not atomic
            default: return nil
        }
        return .raw(buffer)
    }
}
