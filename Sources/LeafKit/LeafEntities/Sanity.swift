// MARK: - Internal Sanity Checkers

internal extension String {
    func _sanity() {
        precondition(!isLeafKeyword, "Name cannot be Leaf keyword")
        precondition(isValidLeafIdentifier, "Name must be valid Leaf identifier")
    }
}

internal extension LeafMethod {
    /// Verify that the method's signature isn't empty and passes sanity
    static func _sanity() {
        let m = Self.self is LeafMutatingMethod.Type
        let nm = Self.self is LeafNonMutatingMethod.Type
        precondition(m != nm,
                     "Adhere strictly to one and only one of LeafMutating/NonMutatingMethod")
        precondition(!callSignature.isEmpty,
                     "Method must have at least one parameter")
        precondition(callSignature.first!.label == nil,
                     "Method's first parameter cannot be labeled")
        precondition(callSignature.first!.defaultValue == nil,
                     "Method's first parameter cannot be defaulted")
        precondition(m ? !invariant : true,
                     "Mutating methods cannot be invariant")
        callSignature._sanity()
    }
}

internal extension Array where Element == LeafCallParameter {
    /// Veryify the `CallParameters` is valid
    func _sanity() {
        precondition(self.count < 256,
                     "Functions may not have more than 255 parameters")
        precondition(0 == self.compactMap({$0.label}).count -
                          Set(self.compactMap { $0.label }).count,
                     "Labels must be unique")
        precondition(self.enumerated().allSatisfy({
                        $0.element.label != nil ||
                        $0.offset < self.enumerated().first(where:
                            {$0.element.label != nil})?
                                .offset ?? endIndex}),
                     "All after first labeled parameter must also be labeled")
        precondition(self.enumerated().allSatisfy({
                        $0.element.defaultValue != nil ||
                        $0.offset < self.enumerated().first(where:
                            {$0.element.defaultValue != nil})?
                                .offset ?? endIndex}),
                     "All after first defaulted parameter must also be defaulted")
    }

    /// Compare two signatures and return true if they can be confused
    func confusable(with: Self) -> Bool {
        if isEmpty && with.isEmpty { return true }
        
        var s = self
        var w = with
        if s.count < w.count { swap(&s, &w) }
        
        let map = s.indices.map { (s[$0], $0 < w.count ? w[$0] : nil) }
        
        var index = 0
        var a: LeafCallParameter { map[index].0 }
        var b: LeafCallParameter? { map[index].1 }

        while index < map.count {
            defer { index += 1 }
            if let b = b {
                /// If both defaulted, ambiguous
                if a.defaulted && b.defaulted { return true }
                /// One of the two is defaulted. As long as label is different, that's ok
                if a.defaulted || b.defaulted { return a.label == b.label }
                /// Neither is defaulted.
                /// If the labels are not the same, it's unambiguous
                if a.label != b.label { return false }
                /// ... or if no shared types overlap.
                if a.types.intersection(b.types).isEmpty { return false }
            }
            /// If shorter sig is out of params, a's defaulted state determines ambiguity
            else { return a.defaulted }
        }
        /// If we've exhausted (equal number of params, it's ambiguous
        return true
    }
    
    /// If the signature can accept an empty call signature, whether because empty or fully defaulted
    var emptyParamSig: Bool {
        !filter { $0.defaultValue != nil }.isEmpty
    }
}

internal extension ParseSignatures {
    func _sanity() {
        precondition(self.values.enumerated().allSatisfy { sig in
                            self.values.enumerated()
                                .filter { $0.offset > sig.offset }
                                .allSatisfy { $0 != sig }
                        },
            "Parse signatures must be unique")
        self.values.forEach { $0.forEach { $0._sanity() } }
    }
}

internal extension LeafParseParameter {
    func _sanity(_ depth: Int = 0) {
        switch self {
            case .callParameter, .keyword, .unscopedVariable: return
            case .literal:
                preconditionFailure("""
                    Do not use .literal in parse signatures:
                    `instantiate` will receive it in place of `unscopedVariable`
                    """)
            case .expression(let e):
                precondition(depth == 0, "Expression only allowed at top level of signature ")
                precondition((2...3).contains(e.count), "Expression must have 2 or 3 parts")
                e.forEach { $0._sanity(1) }
            case .tuple(let t):
                precondition(depth == 1, "Tuple only allowed when nested in expression")
                t.forEach { $0._sanity(2) }
        }
    }
}

internal extension Array where Element == LeafParseParameter {
    /// Given a specific parseSignature and a parsed tuple, attempt to split into parse parameters & call tuple or nil if not a match
    func splitTuple(_ tuple: LKTuple) -> ([String], LKTuple)? {
        var parse: [String] = []
        var call: LKTuple = .init()

        guard self.count == tuple.count else { return nil }
        var index = 0
        var t: (label: String?, value: LKParameter) { tuple.enumerated[index] }
        var s: LeafParseParameter { self[index] }
        while index < self.count {
            switch (s, t.label, t.value.container) {
                /// Valued parameters where call parameter is expected
                case (.callParameter, .none, _) where t.value.isValued:
                    call.values.append(t.value)
                case (.callParameter, .some, _) where t.value.isValued:
                    call.labels[t.label!] = call.count
                    call.values.append(t.value)
                /// Signature expects a keyword (can't be labeled)
                case (.keyword(let kSet), nil, .keyword(let k))
                    where kSet.contains(k): break
                /// Signature expects an unscoped variable (can't be labeled)
                case (.unscopedVariable, nil, .variable(let v)) where v.isAtomic:
                    parse.append(String(v.member!))
                case (.expression(let sE), nil, .expression(let tE))
                    where tE.form.exp == .custom:
                    let extract: LKTuple = .init([tE.first, tE.second, tE.third].compactMap {$0 != nil ? (nil, $0!) : nil})
                    guard let more = sE.splitTuple(extract) else { return nil }
                    parse.append(contentsOf: more.0)
                    call.append(more.1)
                case (.tuple(let sT), nil, .tuple(let tT))
                    where sT.count == tT.count:
                    guard let more = sT.splitTuple(tT) else { return nil }
                    parse.append(contentsOf: more.0)
                    call.append(more.1)
                default: return nil
            }
            index += 1
        }
        return (parse, call)
    }
}

extension String: Error {}
