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
                     "All after first labeled parameter must also be labled")
        precondition(self.enumerated().allSatisfy({
                        $0.element.defaultValue != nil ||
                        $0.offset < self.enumerated().first(where:
                            {$0.element.defaultValue != nil})?
                                .offset ?? endIndex}),
                     "All after first defaulted parameter must also be defaulted")
    }

    /// Compare two signatures and return true if they can be confused
    func confusable(with: Self) -> Bool {
        /// Exactly equal, always confusable
        if self == with { return true }
        /// Both fully defaulted (or empty), always confusable
        let selfUndef = self.filter { $0.defaultValue == nil }
        let withUndef = with.filter { $0.defaultValue == nil }
        if selfUndef.isEmpty, withUndef.isEmpty { return true }
        /// Unequal number of non-defaults always unambiguous
        if self.count - selfUndef.count != with.count - withUndef.count { return false }
        /// Both have equal, non-zero number of non-defaults
        var index: Int = self.indices.first!
        var a: LeafCallParameter { self[index] }
        var b: LeafCallParameter { with[index] }
        while index < selfUndef.count {
            /// Not confusable if labels aren't the same
            if a.label != b.label { return false }
            /// ... or types at position don't intersect
            if a.types.intersection(b.types).isEmpty { return false }
            index += 1
        }
        return true /// Confusable
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
