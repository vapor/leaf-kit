/// Storage setup equivalent for `$aContext` and its various parts in a Leaf file. Entire dictionary may be
/// set `literal` or discrete value entries inside a variable dictionary could be literal; eg `$context` is
/// a potentially variable context, but `$context.aLiteral` will be set literal (and in ASTs, resolved to its
/// actual value when parsing a template).
internal struct LKContextDictionary {
    var parent: LKVariable
    var values: [String: LKDataValue] = [:]
    var variables: Set<LKVariable>
    var literal: Bool = false
    var frozen: Bool = false
    var all: LKDContainer? = nil
    
    init(parent: LKVariable, literal: Bool = false) {
        self.parent = parent
        self.literal = literal
        self.variables = [parent]
    }
    
    /// Only settable while not frozen
    subscript(key: String) -> LKDataValue? {
        get { values[key] }
        set {
            guard !frozen else { return }
            guard let newValue = newValue else {
                values[key] = nil; variables.remove(parent.extend(with: key)); return }
            guard values[key] == nil else {
                values[key] = newValue; return }
            if key.isValidIdentifier { variables.insert(parent.extend(with: key)) }
            values[key] = newValue
        }
    }
        
    /// Set all values, overwriting any that already exist
    mutating func setValues(_ values: [String: LeafDataRepresentable],
                            allLiteral: Bool = false) {
        literal = allLiteral
        values.forEach {
            if $0.isValidIdentifier { variables.insert(parent.extend(with: $0)) }
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
    mutating func get(_ key: LKVariable) -> LeafData? {
        if !frozen { frozen = true }
        if !variables.contains(key) { return nil }
        if key != parent, let member = key.member {
            if !values[member]!.cached { values[member]!.flatten() }
            return values[member]!.leafData
        }
        if let all = all { return .init(all) }
        for (key, value) in values where !value.cached { values[key]!.flatten() }
        all = .dictionary(values.mapValues {$0.leafData})
        return .init(all!)
    }
    
    mutating func freeze() { frozen = true }
    
    var allVariables: Set<LKVariable> { variables }
}


/// Wrapper for what is essentially deferred evaluation of `LDR` values to `LeafData` as an intermediate
/// structure to allow general assembly of a contextual database that can be used/reused by `LeafRenderer`
/// in various render calls. Values are either `variable` and can be updated/refreshed to their `LeafData`
/// value, or `literal` and are considered globally fixed; ie, once literal, they can/should not be converted
/// back to `variable` as resolved ASTs will have used the pre-existing literal value.
internal struct LKDataValue: LeafDataRepresentable {
    static func variable(_ value: LeafDataRepresentable) -> Self { .init(value) }
    static func literal(_ value: LeafDataRepresentable) -> Self { .init(value, constant: true) }
    
    var isVariable: Bool { container.isVariable }
    var leafData: LeafData { container.leafData }
        
    init(_ value: LeafDataRepresentable, constant: Bool = false) {
        container = constant ? .literal(value.leafData) : .variable(value, nil) }
    
    var cached: Bool {
        if case .variable(_, .none) = container { return false }
        if case .literal(let d) = container, d.isLazy { return false }
        return true
    }
    
    /// Coalesce to a literal
    mutating func flatten() {
        let flat: LKDContainer
        switch container {
            case .variable(let v, let d): flat = d?.container ?? v.leafData.container
            case .literal(let d): flat = d.container
        }
        container = .literal(flat.evaluate)
    }
    
    mutating func update(storedValue: LeafDataRepresentable) throws {
        guard isVariable else { throw err("Value is literal") }
        container = .variable(storedValue, nil)
    }
    
    /// Update stored `LeafData` value for variable values
    mutating func refresh() {
        if case .variable(let t, _) = container { container = .variable(t, t.leafData) } }
        
    /// Uncache stored `LeafData` value for variable values
    mutating func uncache() {
        if case .variable(let t, .some) = container { container = .variable(t, nil) } }
    
    private enum Container: LeafDataRepresentable {
        case literal(LeafData)
        case variable(LeafDataRepresentable, LeafData?)
        
        var isVariable: Bool { if case .variable = self { return true } else { return true } }
        var leafData: LeafData {
            switch self {
                case .variable(_, .some(let v)),
                     .literal(let v)    : return v
                case .variable(_, .none) : return .error(internal: "Value was not refreshed")
            }
        }
    }
    
    private var container: Container
}
