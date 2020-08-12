// MARK: Subject to change prior to 1.0.0 release
//

public final class LeafEntities {
    // MARK: - Public Only
    public static let leaf4Core: LeafEntities = ._leaf4Core
    
    // MARK: - Internal Only
    private static var _leaf4Core: LeafEntities {
        let entities = LeafEntities()
        entities.use(RawSwitch.self , asMeta: "raw")
        entities.use(Define.self    , asMeta: "define")
        entities.use(Define.self    , asMeta: "export")
        entities.use(Evaluate.self  , asMeta: "evaluate")
        entities.use(Evaluate.self  , asMeta: "import")
        entities.use(Inline.self    , asMeta: "inline")
        entities.use(Inline.self    , asMeta: "extend")
        
        entities.use(ForLoop.self     , asBlock: "for")
        entities.use(WhileLoop.self   , asBlock: "while")
        entities.use(RepeatLoop.self  , asBlock: "repeat")
        
        entities.use(IfBlock.self     , asBlock: "if")
        entities.use(ElseIfBlock.self , asBlock: "elseif")
        entities.use(ElseBlock.self   , asBlock: "else")
        
        entities.use(IfBlock.IfFunction(), asFunction: "if")
        
        entities.use(StrToStrMap({$0.lowercased()}), asFunctionAndMethod: "lowercased")
        entities.use(StrToStrMap({$0.uppercased()}), asFunctionAndMethod: "uppercased")
        entities.use(StrStrToBoolMap({$0.hasPrefix($1)}), asFunctionAndMethod: "hasPrefix")
        entities.use(StrStrToBoolMap({$0.hasSuffix($1)}), asFunctionAndMethod: "hasSuffix")
        
        entities.use(StrToIntMap({$0.count}), asFunctionAndMethod: "count")
        entities.use(CollectionToIntMap({$0.count}), asFunctionAndMethod: "count")
        
        entities.use(DictionaryCast(), asFunction: "Dictionary")
        
        return entities
    }
    
    
    /// Factories that produce `.raw` Blocks
    private(set) var rawFactories: [String: RawBlock.Type]
    /// Convenience referent to the default `.raw` Block factory
    var raw: RawBlock.Type { rawFactories[Self.defaultRaw]! }
    
    /// Factories that produce named Blocks
    private(set) var blockFactories: [String: LeafBlock.Type]
    
    /// Function registry
    private(set) var functions: [String: [LeafFunction]]
    
    /// Method registry
    private(set) var methods: [String: [LeafMethod]]
    
    /// Initializer
    /// - Parameter rawHandler: The default factory for `.raw` blocks
    init(rawHandler: RawBlock.Type = ByteBuffer.self) {
        self.rawFactories = [Self.defaultRaw: rawHandler]
        self.blockFactories = [:]
        self.functions = [:]
        self.methods = [:]
    }
    
    /// Register a Block factory
    /// - Parameters:
    ///   - block: A `LeafBlock` adherent (which is not a `RawBlock` adherent)
    ///   - name: The name used to choose this factory - "name: `for`" == `#for():`
    public func use(_ block: LeafBlock.Type, asBlock name: String) {
        if !LKConf.running(fault: "Cannot register new Block factories") {
            name._sanity()
            block.callSignature._sanity()
            if let parseSigs = block.parseSignatures { parseSigs._sanity() }
            precondition(block == RawSwitch.self ||
                         block as? RawBlock.Type == nil,
                         "Register RawBlock factories using `registerRaw(...)`")
            precondition(!blockFactories.keys.contains(name),
                         "A factory named \(name) already exists")
            if let chained = block as? ChainedBlock.Type {
                precondition(chained.chainsTo.filter { $0 != block.self}
                             .allSatisfy({ b in blockFactories.values.contains(where: {$0 == b})}),
                             "All types this block chains to must be registered.")
            }
            blockFactories[name] = block
        }
    }
    
    /// Register a RawBlock factory
    /// - Parameters:
    ///   - block: A `RawBlock` adherent
    ///   - name: The name used to choose this factory - "name: `html`" == `#raw(html, ....):`
    public func use(_ block: RawBlock.Type, asRaw name: String) {
        if !LKConf.running(fault: "Cannot register new Raw factories") {
            name._sanity()
            block.callSignature._sanity()
            precondition(!rawFactories.keys.contains(name),
                         "A raw factory named \(name) already exists")
            rawFactories[name] = block
        }
    }
    
    /// Register a LeafFunction
    /// - Parameters:
    ///   - function: An instance of a `LeafFunction` adherant
    ///   - name: "name: `date`" == `#date()`
    public func use(_ function: LeafFunction, asFunction name: String) {
        if !LKConf.running(fault: "Cannot register new Functions") {
            name._sanity()
            function.sig._sanity()
            if functions.keys.contains(name) {
                functions[name]!.forEach {
                    precondition(!function.sig.confusable(with: $0.sig),
                                 "Function overload would produce ambiguous match")
                }
                functions[name]!.append(function)
            } else { functions[name] = [function] }
        }
    }
    
    /// Register a LeafMethod
    /// - Parameters:
    ///   - method: An instance of a `LeafMethod` adherant
    ///   - name: "name: `hasPrefix`" == `#(a.hasPrefix(b)`
    /// - Throws: If a function for name is already registered, or name is empty
    public func use(_ method: LeafMethod, asMethod name: String) {
        if !LKConf.running(fault: "Cannot register new Methods") {
            name._sanity()
            method.sig._sanity()
            if methods.keys.contains(name) {
                methods[name]!.forEach {
                    precondition(!method.sig.confusable(with: $0.sig),
                                 "Method overload would produce ambiguous match")
                }
                methods[name]!.append(method)
            } else { methods[name] = [method] }
        }
    }
    
    /// Register a LeafMethod as both a Function and a Method
    /// - Parameters:
    ///   - method: An instance of a `LeafMethod` adherant
    ///   - name: "name: `hasPrefix`" == `#hasPrefix(a,b)` && `#(a.hasPrefix(b)`
    /// - Throws: If a function for name is already registered, or name is empty
    public func use(_ method: LeafMethod, asFunctionAndMethod name: String) {
        use(method, asFunction: name)
        use(method, asMethod: name)
    }
    
    func use(_ meta: LKMetaBlock.Type, asMeta name: String) {
        guard blockFactories[name] == nil else { __MajorBug("Metablock already registered") }
        blockFactories[name] = meta
    }
    
    // FIXME - These will pick the *first* of colliding signatures when ambiguous
    // evaluation should re-validate to pick the best possible sig
    func validateFunction(_ name: String,
                          _ params: LKTuple?) -> Result<(LeafFunction, LKTuple), String> {
        guard let functions = functions[name] else { return .failure("No function \(name)") }
        for function in functions {
            if let tuple = try? validateTupleCall(params, function.sig).get() {
                return .success((function, tuple))
            } else { continue }
        }
        return .failure("No matching function; \(functions.count) candidate(s)")
    }
    
    func validateMethod(_ name: String,
                        _ params: LKTuple?) -> Result<(LeafFunction, LKTuple), String> {
        guard let methods = methods[name] else { return .failure("No method \(name)") }
        for method in methods {
            if let tuple = try? validateTupleCall(params, method.sig).get() {
                return .success((method, tuple))
            } else { continue }
        }
        return .failure("No matching method; \(methods.count) candidate(s)")
    }
    
    func validateBlock(_ name: String,
                       _ params: LKTuple?) -> Result<(LeafFunction, LKTuple), String> {
        guard blockFactories[name] != RawSwitch.self else { return validateRaw(params) }
        guard let factory = blockFactories[name] else { return .failure("\(name) is not a block factory") }
        let block: LeafFunction?
        var call: LKTuple = .init()
    
        validate: if let parseSigs = factory.parseSignatures {
            for (name, sig) in parseSigs {
                guard let match = sig.splitTuple(params ?? .init()) else { continue }
                guard let created = try? factory.instantiate(name, match.0) else {
                    return .failure("Parse signature matched but couldn't instantiate")}
                block = created
                call = match.1
                break validate
            }
            block = nil
        } else if let params = params ?? call, params.count == factory.callSignature.count {
            call = params
            block = try? factory.instantiate(nil, [])
        } else { return .failure("Factory doesn't take parameters") }
        
        guard let function = block else { return .failure("Parameters don't match parse signature") }
        let validate = validateTupleCall(call, function.sig)
        switch validate {
            case .failure(let message): return .failure("\(name) couldn't be parsed: \(message)")
            case .success(let tuple): return .success((function, tuple))
        }
    }
    
    func validateRaw(_ params: LKTuple?) -> Result<(LeafFunction, LKTuple), String> {
        var name = Self.defaultRaw
        var call: LKTuple
        
        if let params = params {
            if case .variable(let v) = params[0]?.container, v.atomic { name = String(v.member!) }
            else { return .failure("Specify raw handler with unquoted name") }
            call = params
            call.values.removeFirst()
            call.labels = call.labels.mapValues { $0 - 1 }
        } else { call = .init() }
        
        guard let factory = rawFactories[name] else { return .failure("\(name) is not a raw handler")}
        guard call.values.allSatisfy({ $0.data != nil }) else {
            return .failure("Raw handlers currently require concrete data parameters") }
        let validate = validateTupleCall(call, factory.callSignature)
        switch validate {
            case .failure(let message): return .failure("\(name) couldn't be parsed: \(message)")
            case .success(let tuple): return .success((RawSwitch(factory, tuple), .init()))
        }
    }
    
    func validateTupleCall(_ tuple: LKTuple?, _ expected: [CallParameter]) -> Result<LKTuple, String> {
        /// True if actual parameter matches expected parameter value type, or if actual parameter is uncertain type
        func matches(_ actual: LKParameter, _ expected: CallParameter) -> Bool {
            guard let t = actual.baseType else { return true }
            return expected.types.contains(t) ? true
                 : expected.types.first(where: {t.casts(to: $0) != .ambiguous}) != nil
        }
        func output() -> Result<LKTuple, String> {
            for i in 0 ..< count.out {
                if temp[i] == nil { return .failure("Missing parameter \(expected[i].description)") }
                tuples.out.values.append(temp[i]!)
            }
            return .success(tuples.out)
        }
        
        guard expected.count < 256 else { return .failure("Can't have more than 255 params") }
        
        var tuples = (in: tuple ?? LKTuple(), out: LKTuple())

        // All input must be valued types
        guard tuples.in.values.allSatisfy({$0.isValued}) else {
            return .failure("Parameters must all be value types") }
        
        let count = (in: tuples.in.count, out: expected.count)
        let defaults = expected.compactMap({ $0.defaultValue }).count
        // Guard that in.count <= out.count && in.count + default >= out.count
        if count.in > count.out { return .failure("Too many parameters") }
        if Int(count.in) + defaults < count.out { return .failure("Not enough parameters") }

        // guard that if the signature has labels, input is fully contained and in order
        let labels = (in: tuples.in.labels.keys, out: expected.compactMap {$0.label})
        guard labels.out.filter({labels.in.contains($0)}).elementsEqual(labels.in),
              Set(labels.out).isSuperset(of: labels.in) else { return .failure("Label mismatch") }
    
        var temp: [LKParameter?] = .init(repeating: nil, count: expected.count)
        
        // Copy all labels to out and labels and/or default values to temp
        for (i, p) in expected.enumerated() {
            if let label = p.label { tuples.out.labels[label] = i }
            if let data = p.defaultValue { temp[i] = .value(data) }
        }
        
        // If input is empty, all default values are already copied and we can output
        if count.in == 0 { return output() }
        
        // Map labeled input parameters to their correct position in the temp array
        for label in labels.in { temp[Int(tuples.out.labels[label]!)] = tuples.in[label] }

        // At this point any nil value in the temp array is undefaulted, and
        // the only values uncopied from tuple.in are unlabeled values
        var index = 0
        let last = (in: (tuples.in.labels.values.min() ?? count.in) - 1,
                    out: (tuples.out.labels.values.min() ?? count.out) - 1)
        while index <= last.in, index <= last.out {
            let param = tuples.in.values[index]
            // apply all unlabeled input params to temp, unsetting if not matching expected
            temp[index] = matches(param, expected[index]) ? param : nil
            if temp[index] == nil { break }
            index += 1
        }
        return output()
    }

    internal static let defaultRaw: String = "default"
    
    
    
}

// MARK: - Internal Sanity Checkers

internal extension String {
    func _sanity() {
        precondition(isValidIdentifier, "Name must be valid Leaf identifier")
        precondition(LeafKeyword(rawValue: self) == nil, "Name cannot be Leaf keyword")
    }
}

internal extension LeafFunction {
    var invariant: Bool { Self.invariant }
    var sig: [CallParameter] { Self.callSignature }
}

internal extension LeafMethod {
    /// Verify that the method's signature isn't empty and passes sanity
    static func _sanity() {
        precondition(!callSignature.isEmpty,
                     "Method must have at least one parameter")
        precondition(callSignature.first!.label == nil,
                     "Method's first parameter cannot be labeled")
        precondition(callSignature.first!.defaultValue == nil,
                     "Method's first parameter cannot be defaulted")
        precondition(callSignature.first!.optional == false,
                     "Method's first parameter cannot be optional")
        callSignature._sanity()
    }
}

internal extension CallParameter {
    /// Verify the `CallParameter` is valid
    func _sanity() {
        precondition(!types.isEmpty,
                     "Parameter must specify at least one type")
        precondition(!types.contains(.void),
                     "Parameters cannot take .void types")
        precondition(!(label?.isEmpty ?? false) && label != "_",
                     "Use nil for unlabeled parameters, not empty strings or _")
        precondition(label?.isValidIdentifier ?? true &&
                     LeafKeyword(rawValue: label ?? "") == nil,
                     "Label must be a valid, non-keyword Leaf identifier")
        precondition(types.contains(defaultValue?.celf ?? types.first!),
                     "Default value is not a match for the argument types")
    }
}

internal extension Array where Element == CallParameter {
    /// Veryify the `[CallParameter]` is valid
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
        // Exactly equal, always confusable
        if self == with { return true }
        // Both fully defaulted (or empty), always confusable
        let selfUndef = self.filter { $0.defaultValue == nil }
        let withUndef = with.filter { $0.defaultValue == nil }
        if selfUndef.isEmpty, withUndef.isEmpty { return true }
        // Unequal number of non-defaults always unambiguous
        if self.count - selfUndef.count != with.count - withUndef.count { return false }
        // Both have equal, non-zero number of non-defaults
        var index: Int = self.indices.first!
        var a: CallParameter { self[index] }
        var b: CallParameter { with[index] }
        while index < selfUndef.count {
            // Not confusable if labels aren't the same
            if a.label != b.label { return false }
            // ... or types at position don't intersect
            if a.types.intersection(b.types).isEmpty { return false }
            index += 1
        }
        return true // Confusable
    }
}

internal extension Dictionary where Key == String, Value == [ParseParameter] {
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

internal extension ParseParameter {
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

internal extension Array where Element == ParseParameter {
    /// Given a specific parseSignature and a parsed tuple, attempt to split into parse parameters & call tuple or nil if not a match
    func splitTuple(_ tuple: LKTuple) -> ([String], LKTuple)? {
        var parse: [String] = []
        var call: LKTuple = .init()
        
        guard self.count == tuple.count else { return nil }
        var index = 0
        var t: (label: String?, value: LKParameter) { tuple.enumerated[index] }
        var s: ParseParameter { self[index] }
        while index < self.count {
            switch (s, t.label, t.value.container) {
                // Valued parameters where call parameter is expected
                case (.callParameter, .none, _) where t.value.isValued:
                    call.values.append(t.value)
                case (.callParameter, .some, _) where t.value.isValued:
                    call.labels[t.label!] = call.count
                    call.values.append(t.value)
                // Signature expects a keyword (can't be labeled)
                case (.keyword(let kSet), nil, .keyword(let k))
                    where kSet.contains(k): break
                // Signature expects an unscoped variable (can't be labeled)
                case (.unscopedVariable, nil, .variable(let v)) where v.atomic:
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
