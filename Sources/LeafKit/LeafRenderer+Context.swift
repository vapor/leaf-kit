public extension LeafRenderer.Context {
    init(_ context: [String: LeafDataRepresentable]) { try! setValues(to: context) }
    
    init(dictionaryLiteral elements: (String, LeafDataRepresentable)...) {
        self = .init(.init(uniqueKeysWithValues: elements)) }
    
    init(dictionaryLiteral elements: (String, LeafData)...) {
        self = .init(.init(uniqueKeysWithValues: elements)) }
    
    /// Set the contextual values for a specific valid scope, overwriting if any exist.
    ///
    /// If scope already exists as a literal but LeafKit is running, update will fail. Will initialize context
    /// scope if it does not already exist.
    mutating func setValues(for scope: String = defaultContextScope,
                            to values: [String: LeafDataRepresentable],
                            allLiteral: Bool = false) throws {
        if scope == LKVariable.selfScope && allLiteral { throw err("`self` cannot be constant") }
        let scopeVar = try getScopeKey(scope)
        let constantScope = contexts[scopeVar]?.literal ?? false
        if constantScope {
            guard !LKConf.isRunning else {
                throw err("\(scope) is a constant scoped context and cannot be updated") }
            assert(allLiteral,
                   "\(scope) already exists as a constant scope - setting values is implicitly constant")
        }
        if contexts[scopeVar] == nil {
            contexts[scopeVar] = .init(parent: scopeVar, literal: allLiteral) }
        contexts[scopeVar]!.setValues(values, allLiteral: allLiteral)
    }
    
    /// Set a specific value (eg `$app.variableName`) where scope == "app" and id = "variableName"
    ///
    /// If the value is already set, will overwrite the existing value (unless the value or its scope is
    /// globally literal *and* LeafKit is already running; literal values may be updated freely prior
    /// to LeafKit starting)
    mutating func setVariable(in scope: String = defaultContextScope,
                              for id: String,
                              to value: LeafDataRepresentable,
                              isLiteral: Bool = false) throws {
        guard id.isValidIdentifier else { throw err(.invalidIdentifier(id)) }
        try setValue(in: scope, at: id, to: value, isLiteral: isLiteral)
    }
    
    /// For complicated objects being passed in context to Leaf that may have expensive calculation, generators
    /// are preferred as they will only be accessed and calculated if the template actually uses the variable.
    ///
    /// No option for setting as `literal` because doing so is functionally pointless - literal values are always
    /// flattened globally, so there's no benefit to doing it unless usage dictates the values will not change.
    mutating func setLazyValues(in scope: String = defaultContextScope,
                                to generators: [String: () -> LeafData]) throws {
        let data = generators.mapValues { f in LeafData.lazy({f()}, returns: .void) }
        try setValues(for: scope, to: data)
    }
    
    /// Set a specific value (eg `$app[key]`) to new value; follows same rules as `setVariable`
    ///
    /// `setVariable` is to be preferred as it ensures the identifier is a valid key. While keys that
    /// are valid variable names will be published to Leaf (eg, `$app.id`), invalid identifiers will only
    /// be accessible by subscripting.
    ///
    /// If the value is already set, will overwrite the existing value (unless the value or its scope is
    /// globally constant *and* LeafKit is already running; literal values may be updated freely prior
    /// to LeafKit starting with the caveat that, once declared or locked as literal, it may no longer be
    /// reverted to a variable)
    mutating func setValue(in scope: String = defaultContextScope,
                           at key: String,
                           to value: LeafDataRepresentable,
                           isLiteral: Bool = false) throws {
        guard !key.isEmpty else { throw err("Value key must not be empty string") }
        let scopeVar = try getScopeKey(scope)
        guard isUpdateable(scopeVar, key) else { throw err("\(scope)[\(key)] is not settable") }
        if let isVariable = contexts[scopeVar]?[key]?.isVariable, !isVariable && !isLiteral {
            throw err("\(scope)[\(key)] was already declared as constant - cannot change to variable")
        }
        self[scopeVar, key] = isLiteral ? .literal(value.leafData) : .variable(value)
    }
    
    /// Update an already existing value and maintain its variable/literal state
    mutating func updateValue(in scope: String = defaultContextScope,
                              at key: String,
                              to value: LeafDataRepresentable) throws {
        let scopeVar = try validateScope(scope)
        guard let isVariable = contexts[scopeVar]![key]?.isVariable else {
            throw err("Value must already be set to update") }
        guard isVariable || !LKConf.isRunning else {
            throw err("Constant context values cannot be updated after LeafKit starts") }
        contexts[scopeVar]![key] = isVariable ? .variable(value) : .literal(value)
    }
    
    /// Lock an existing value as globally literal
    mutating func lockAsLiteral(key: String,
                                in scope: String = defaultContextScope) throws {
        let scopeVar = try validateScope(scope)
        if contexts[scopeVar]![key] == nil { throw nonExistant(scope, key) }
        contexts[scopeVar]!.setLiteral(key)
    }
    
    /// Lock an entire existing scope and all its contained values as globally literal
    mutating func lockAsLiteral(scope: String) throws {
        let scopeVar = try validateScope(scope)
        contexts[scopeVar]!.setLiteral()
    }
    
    /// Cache the current value of `leafData` in context for an existing key
    ///
    /// Only applicable for variable values; locking a scope or value as literal, or declaring as such,
    /// inherently caches the value
    mutating func cacheValue(in scope: String = defaultContextScope,
                             at key: String) throws {
        let scopeVar = try validateScope(scope)
        if contexts[scopeVar]![key] == nil { throw nonExistant(scope, key) }
        contexts[scopeVar]![key]!.refresh()
    }
    
    /// Register a Swift object to the context, published to `LeafUnsafeEntity.externalObjects[key]`
    /// during serialize. When `contextualize` is true, the object (if it adheres to `LeafContextPublisher`
    /// or `LeafDataRepresentable` and resolves to `LeafData.dictionary`) will automatically
    /// provide its presented values to a rendered template as variables in the `$key` scoped context
    mutating func register(object: Any?,
                           as key: String,
                           contextualize: Bool = true) throws {
        externalObjects[key] = object
        if contextualize && object == nil, let scope = try? validateScope(key) {
            defer { contexts[scope] = nil }
            guard LKConf.isRunning else { return }
            guard let ctx = contexts[scope], !ctx.literal else {
                throw err("\(key) is a literal scope - cannot be unset") }
            guard ctx.values.allSatisfy({$0.value.isVariable}) else {
                throw err("\(key) has literal values - cannot be unset") }
        } else if contextualize, key.isValidIdentifier, let object = object {
            if let contextualizing = object as? LeafContextPublisher {
                try setLazyValues(in: key,
                                  to: contextualizing.coreVariables()
                                                     .merging(contextualizing.extendedVariables()) {_, b in b})
            }
            else if let data = (object as? LeafData)?.leafData.dictionary {
                try setValues(for: key, to: data) }
            else { assertionFailure("A registered external object must be either `LeafContextualizing` or `LeafDataRepresentable` vending a dictionary when `contextualize: true`") }
        }
    }
    
//    /// Register an object
//    subscript(objectKey: String) -> Any? {
//        get { externalObjects[objectKey] }
//        set { externalObjects[objectKey] = newValue }
//    }
}

internal extension LeafRenderer.Context {
    /// Return a filtered version of the context that holds only literal values for parse stage
    var literalsOnly: Self {
        var contexts = self.contexts
        for (scope, context) in contexts {
            if context.literal { continue }
            context.values.forEach { k, v in if v.isVariable { contexts[scope]![k] = nil } }
        }
        return .init(contexts: contexts)
    }
    
    
    func nonExistant(_ scope: String, _ key: String? = nil) -> LeafError {
        err("\(scope)\(key != nil ? "[\(key!)]" : "") does not exist in context") }
    
    func validateScope(_ scope: String) throws -> LKVariable {
        let scopeVar = try getScopeKey(scope)
        guard contexts[scopeVar] != nil else { throw err("\(scopeVar) does not exist in context") }
        return scopeVar
    }
    
    func getScopeKey(_ scope: String) throws -> LKVariable {
        guard scope.isValidIdentifier else { throw err(.invalidIdentifier(scope)) }
        return .scope(scope)
    }
    
    func isUpdateable(_ scope: LKVariable, _ key: String) -> Bool {
        if contexts[scope]?.frozen ?? false { return false }
        if contexts[scope]?.literal ?? false && LKConf.isRunning { return false }
        return self[scope, key]?.isVariable ?? true || !LKConf.isRunning
    }
    
    var allVariables: Set<LKVariable> { contexts.values.reduce(into: []) {$0.formUnion($1.allVariables)} }
    
    /// Directly retrieve single value from a context by LKVariable; only use when user can no longer edit structure.
    mutating func get(_ key: LKVariable) -> LeafData? {
        contexts[.scope(key.scope!)]?.get(key) ?? .error(internal: "No value for \(key.description) in context")
    }
    
    subscript(_ scope: LKVariable, _ variable: String) -> LKDataValue? {
        get { contexts[scope]?[variable] }
        set {
            if contexts[scope] == nil { contexts[scope] = .init(parent: scope) }
            contexts[scope]![variable] = newValue
        }
    }
}
