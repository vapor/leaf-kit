// MARK: Subject to change prior to 1.0.0 release
import Foundation

public final class LeafEntities {
    // MARK: - Public Only
    public static let leaf4Core: LeafEntities = ._leaf4Core
    public static let leaf4Transitional: LeafEntities = ._leaf4Transitional

    // MARK: - Internal Only
    private static var _leaf4Core: LeafEntities {
        let entities = LeafEntities()
        
        entities.registerMetaBlocks()
        entities.registerControlFlow()
        
        entities.registerTypeCasts()

        entities.registerArrayReturns()
        entities.registerBoolReturns()
        entities.registerIntReturns()
        entities.registerDoubleReturns()
        entities.registerStringReturns()
        entities.registerMutatingMethods()
        
        entities.registerMisc()
        
        return entities
    }
    
    private static var _leaf4Transitional: LeafEntities {
        let entities = _leaf4Core
        entities.use(Define.self   , asMeta: "export")
        entities.use(Evaluate.self , asMeta: "import")
        entities.use(Inline.self   , asMeta: "extend")
        
        return entities
    }


    /// Factories that produce `.raw` Blocks
    private(set) var rawFactories: [String: LKRawBlock.Type]
    /// Convenience referent to the default `.raw` Block factory
    var raw: LKRawBlock.Type { rawFactories[Self.defaultRaw]! }

    /// Factories that produce named Blocks
    private(set) var blockFactories: [String: LeafBlock.Type]

    /// Function registry
    private(set) var functions: [String: [LeafFunction]]

    /// Method registry
    private(set) var methods: [String: [LeafMethod]]
    
    /// Type registery
    internal private(set) var types: [String: (LeafDataRepresentable.Type, LeafDataType)]

    /// Initializer
    /// - Parameter rawHandler: The default factory for `.raw` blocks
    init(rawHandler: LKRawBlock.Type = LeafBuffer.self) {
        self.rawFactories = [Self.defaultRaw: rawHandler]
        self.blockFactories = [:]
        self.functions = [:]
        self.methods = [:]
        self.types = [:]
    }
    
    internal func use<T>(_ swiftType: T.Type,
                         asType name: String,
                         storeAs: LeafDataType) where T: LeafDataRepresentable {
        if !LKConf.running(fault: "Cannot register new types") {
            precondition(storeAs != .void, "Void is not a valid storable type")
            precondition(!types.keys.contains(name),
                         "\(name) is already registered for \(String(describing: types[name]))")
            switch storeAs {
                case .array      : use(ArrayIdentity(), asFunction: name)
                case .bool       : use(BoolIdentity(), asFunction: name)
                case .data       : use(DataIdentity(), asFunction: name)
                case .dictionary : use(DictionaryIdentity(), asFunction: name)
                case .double     : use(DoubleIdentity(), asFunction: name)
                case .int        : use(IntIdentity(), asFunction: name)
                case .string     : use(StringIdentity(), asFunction: name)
                case .void       : __MajorBug("Void is not a valid storable type")
            }
        }
    }

    /// Register a Block factory
    /// - Parameters:
    ///   - block: A `LeafBlock` adherent (which is not a `LKRawBlock` adherent)
    ///   - name: The name used to choose this factory - "name: `for`" == `#for():`
    public func use(_ block: LeafBlock.Type, asBlock name: String) {
        if !LKConf.running(fault: "Cannot register new Block factories") {
            name._sanity()
            block.callSignature._sanity()
            if let parseSigs = block.parseSignatures { parseSigs._sanity() }
            precondition(block == RawSwitch.self ||
                         block as? LKRawBlock.Type == nil,
                         "Register LKRawBlock factories using `registerRaw(...)`")
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

    /// Register a LKRawBlock factory
    /// - Parameters:
    ///   - block: A `LKRawBlock` adherent
    ///   - name: The name used to choose this factory - "name: `html`" == `#raw(html, ....):`
    internal func use(_ block: LKRawBlock.Type, asRaw name: String) {
        if !LKConf.running(fault: "Cannot register new Raw factory \(name)") {
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
        if !LKConf.running(fault: "Cannot register new function \(name)") {
            name._sanity()
            function.sig._sanity()
            precondition(!((function as? LeafMethod)?.mutating ?? false),
                         "Mutating method \(type(of: function)) may not be used as direct functions")
            if functions.keys.contains(name) {
                functions[name]!.forEach {
                    precondition(!function.sig.confusable(with: $0.sig),
                                 "Function overload is ambiguous with \(type(of: $0))")
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
        if !LKConf.running(fault: "Cannot register new method \(name)") {
            name._sanity()
            method.sig._sanity()
            type(of: method)._sanity()
            if methods.keys.contains(name) {
                methods[name]!.forEach {
                    precondition(!method.sig.confusable(with: $0.sig),
                                 "Method overload is ambiguous with \(type(of: $0))")
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

    /// Return all valid matches.
    func validateFunction(_ name: String,
                          _ params: LKTuple?) -> Result<[(LeafFunction, LKTuple?)], String> {
        guard let functions = functions[name] else { return .failure("No function named `\(name)` exists") }
        var valid: [(LeafFunction, LKTuple?)] = []
        for function in functions {
            if let tuple = try? validateTupleCall(params, function.sig).get()
            { valid.append((function, tuple.isEmpty ? nil : tuple)) } else { continue }
        }
        if valid.isEmpty { return .failure(parseErr(.sameName("function", name, functions.map{$0.sig.short})).description) }
        return .success(valid)
    }

    func validateMethod(_ name: String,
                        _ params: LKTuple?,
                        _ mutable: Bool) -> Result<[(LeafFunction, LKTuple?)], String> {
        guard let methods = methods[name] else { return .failure("No method named `\(name)` exists") }
        var valid: [(LeafFunction, LKTuple?)] = []
        var mutatingMismatch = false
        for method in methods {
            if method.mutating && !mutable { mutatingMismatch = true; continue }
            if let tuple = try? validateTupleCall(params, method.sig).get()
            { valid.append((method, tuple.isEmpty ? nil : tuple)) } else { continue }
        }
        if valid.isEmpty {
            let additional = mutatingMismatch ? "\nPotential mutating matches for \(name) but operand is immutable" : ""
            return .failure("\(parseErr(.sameName("function", name, methods.map{$0.sig.short})).description)\(additional)")
        }
        return .success(valid)
    }

    func validateBlock(_ name: String,
                       _ params: LKTuple?) -> Result<(LeafFunction, LKTuple?), String> {
        guard blockFactories[name] != RawSwitch.self else { return validateRaw(params) }
        guard let factory = blockFactories[name] else { return .failure("No block named `\(name)` exists") }
        let block: LeafFunction?
        var call: LKTuple = .init()

        validate:
        if let parseSigs = factory.parseSignatures {
            for (name, sig) in parseSigs {
                guard let match = sig.splitTuple(params ?? .init()) else { continue }
                guard let created = try? factory.instantiate(name, match.0) else {
                    return .failure("Parse signature matched but couldn't instantiate")}
                block = created
                call = match.1
                break validate
            }
            block = nil
        } else if (params?.count ?? 0) == factory.callSignature.count {
            if let params = params { call = params }
            block = try? factory.instantiate(nil, [])
        } else { return .failure("Factory doesn't take parameters") }

        guard let function = block else { return .failure("Parameters don't match parse signature") }
        let validate = validateTupleCall(call, function.sig)
        switch validate {
            case .failure(let message): return .failure("\(name) couldn't be parsed: \(message)")
            case .success(let tuple): return .success((function, !tuple.isEmpty ? tuple : nil))
        }
    }

    func validateRaw(_ params: LKTuple?) -> Result<(LeafFunction, LKTuple?), String> {
        var name = Self.defaultRaw
        var call: LKTuple

        if let params = params {
            if case .variable(let v) = params[0]?.container, v.isAtomic { name = String(v.member!) }
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
            case .success(let tuple): return .success((RawSwitch(factory, tuple), nil))
        }
    }

    func validateTupleCall(_ tuple: LKTuple?, _ expected: [LeafCallParameter]) -> Result<LKTuple, String> {
        /// True if actual parameter matches expected parameter value type, or if actual parameter is uncertain type
        func matches(_ actual: LKParameter, _ expected: LeafCallParameter) -> Bool {
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

        /// All input must be valued types
        guard tuples.in.values.allSatisfy({$0.isValued}) else {
            return .failure("Parameters must all be value types") }

        let count = (in: tuples.in.count, out: expected.count)
        let defaults = expected.compactMap({ $0.defaultValue }).count
        /// Guard that in.count <= out.count && in.count + default >= out.count
        if count.in > count.out { return .failure("Too many parameters") }
        if Int(count.in) + defaults < count.out { return .failure("Not enough parameters") }

        /// guard that if the signature has labels, input is fully contained and in order
        let labels = (in: tuples.in.enumerated.compactMap {$0.label}, out: expected.compactMap {$0.label})
        guard labels.out.filter({labels.in.contains($0)}).elementsEqual(labels.in),
              Set(labels.out).isSuperset(of: labels.in) else { return .failure("Label mismatch") }

        var temp: [LKParameter?] = .init(repeating: nil, count: expected.count)

        /// Copy all labels to out and labels and/or default values to temp
        for (i, p) in expected.enumerated() {
            if let label = p.label { tuples.out.labels[label] = i }
            if let data = p.defaultValue { temp[i] = .value(data) }
        }

        /// If input is empty, all default values are already copied and we can output
        if count.in == 0 { return output() }

        /// Map labeled input parameters to their correct position in the temp array
        for label in labels.in { temp[Int(tuples.out.labels[label]!)] = tuples.in[label] }

        /// At this point any nil value in the temp array is undefaulted, and
        /// the only values uncopied from tuple.in are unlabeled values
        var index = 0
        let last = (in: (tuples.in.labels.values.min() ?? count.in) - 1,
                    out: (tuples.out.labels.values.min() ?? count.out) - 1)
        while index <= last.in, index <= last.out {
            let param = tuples.in.values[index]
            /// apply all unlabeled input params to temp, unsetting if not matching expected
            temp[index] = matches(param, expected[index]) ? param : nil
            if temp[index] == nil { break }
            index += 1
        }
        return output()
    }

    static let defaultRaw: String = "raw"
}

// MARK: - Internal Sanity Checkers

internal extension String {
    func _sanity() {
        precondition(isValidIdentifier, "Name must be valid Leaf identifier")
        precondition(LeafKeyword(rawValue: self) == nil, "Name cannot be Leaf keyword")
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
