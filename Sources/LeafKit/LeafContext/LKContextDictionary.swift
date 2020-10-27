/// Storage setup equivalent for `$aContext` and its various parts in a Leaf file. Entire dictionary may be
/// set `literal` or discrete value entries inside a variable dictionary could be literal; eg `$context` is
/// a potentially variable context, but `$context.aLiteral` will be set literal (and in ASTs, resolved to its
/// actual value when parsing a template).
internal struct LKContextDictionary {
    /// Scope parent
    let parent: LKVariable
    /// Only returns top level scope & atomic variables to defer evaluation of values
    private(set) var values: [String: LKDataValue] = [:]
    private(set) var allVariables: Set<LKVariable>
    private(set) var literal: Bool = false
    private(set) var frozen: Bool = false
    private var cached: LKVarTable = [:]
    
    init(parent: LKVariable, literal: Bool = false) {
        self.parent = parent
        self.literal = literal
        self.allVariables = [parent]
    }
    
    /// Only settable while not frozen
    subscript(key: String) -> LKDataValue? {
        get { values[key] }
        set {
            guard !frozen else { return }
            defer { cached[parent] = nil }
            guard let newValue = newValue else {
                values[key] = nil; allVariables.remove(parent.extend(with: key)); return }
            guard values[key] == nil else {
                values[key] = newValue; return }
            if key.isValidLeafIdentifier { allVariables.insert(parent.extend(with: key)) }
            values[key] = newValue
        }
    }
        
    /// Set all values, overwriting any that already exist
    mutating func setValues(_ values: [String: LeafDataRepresentable],
                            allLiteral: Bool = false) {
        literal = allLiteral
        values.forEach {
            if $0.isValidLeafIdentifier { allVariables.insert(parent.extend(with: $0)) }
            self[$0] = allLiteral ? .literal($1) : .variable($1)
        }
    }
    
    /// With empty string, set entire object & all values to constant & freeze; with key string, set value to constant
    mutating func setLiteral(_ key: String? = nil) {
        func setSpecific(_ key: String) { self[key]!.flatten() }
        if let key = key { if values.keys.contains(key) { setSpecific(key) }; return }
        for (key, val) in values where !val.cached { self[key]!.flatten() }
        literal = true
    }
    
    /// Only updatable while not frozen
    mutating func updateValue(key: String, to value: LeafDataRepresentable) {
        guard !frozen && values.keys.contains(key) else { return }
        if self[key]!.isVariable { try! self[key]!.update(storedValue: value) }
        else { self[key] = .literal(value.leafData) }
    }

    /// Obtain `[LKVariable: LeafData]` for variable; freezes state of context as soon as accessed
    ///
    /// If a specific variable, flatten result if necessary and return that element
    /// If the parent variable, return a dictionary data elelement for the entire scope, and cached copies of
    /// individually referenced objects
    mutating func match(_ key: LKVariable) -> LeafData? {
        if let hit = cached[key] { return hit }
        
        if key.isPathed {
            let root = key.ancestor
            if !allVariables.contains(root) || match(root) == nil { return nil }
            return cached.match(key)
        }
        else if !allVariables.contains(key) { return nil }
        
        frozen = true
        
        let value: LeafData?
        if key == parent {
            for (key, value) in values where !value.cached { values[key]!.flatten() }
            value = .dictionary(values.mapValues {$0.leafData})
        } else {
            let member = key.member!
            if !values[member]!.cached { values[member]!.flatten() }
            value = values[member]!.leafData
        }
        cached[key] = value
        return value
    }
}
