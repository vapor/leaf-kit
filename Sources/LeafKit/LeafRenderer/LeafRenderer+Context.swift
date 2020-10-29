public extension LeafRenderer.Context {
    static func emptyContext(isRoot: Bool = false) -> Self { .init(isRootContext: isRoot) }
    
    /// Initialize a context with the given dictionary assigned to `self`
    init(_ context: [String: LeafDataRepresentable], isRoot: Bool = false) {
        self.isRootContext = isRoot
        try! setValues(to: context)
    }
    
    /// Initialize a context with the given dictionary literal assigned to `self`
    init(dictionaryLiteral elements: (String, LeafDataRepresentable)...) {
        self = .init(.init(uniqueKeysWithValues: elements)) }
    
    /// Initialize a context with the given dictionary literal assigned to `self`
    init(dictionaryLiteral elements: (String, LeafData)...) {
        self = .init(.init(uniqueKeysWithValues: elements)) }
    
    /// Failable initialize from `Encodable`objects
    init?(encodable: [String: Encodable], isRoot: Bool = false) {
        let context = try? encodable.mapValues { e -> LeafDataRepresentable in
            let encoder = LKEncoder()
            try e.encode(to: encoder)
            return encoder
        }
        guard context != nil else { return nil }
        self.init(context!, isRoot: isRoot)
    }
    
    /// Failable intialize `self` scope from `Encodable` object that returns a keyed container
    init?(encodable asSelf: Encodable, isRoot: Bool = false) {
        let encoder = LKEncoder()
        guard (try? asSelf.encode(to: encoder)) != nil,
              let dict = encoder.root?.leafData.dictionary else { return nil }
        self.init(dict, isRoot: isRoot)
    }
    
    static var defaultContextScope: String { LKVariable.selfScope }
        
    subscript(scope scope: String = defaultContextScope, key: String) -> LeafDataRepresentable? {
        get { self[.scope(scope), key] }
        /// Public subscriptor for context values will silently fail if the scope is invalid or an existing value is not updatable
        set {
            guard !scope.isEmpty && !key.isEmpty,
                  !blocked(in: scope).contains(key),
                  let scope = try? getScopeKey(scope),
                  isUpdateable(scope, key) else { return }
            let literal = !(self[scope, key]?.isVariable ?? true)
            self[scope, key] = newValue != nil ? .init(newValue!, literal) : nil
        }
    }
        
    /// Set a specific value (eg `$app[key]`) to new value; follows same rules as `setVariable`
    ///
    /// Keys that are valid variable names will be published to Leaf (eg, `$app.id`); invalid identifiers will
    /// only be accessible by subscripting.
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
        try setValues(in: scope, to: [key: value], allLiteral: isLiteral)
    }
    
    /// Set the contextual values for a specific valid scope, overwriting if any exist.
    ///
    /// If scope already exists as a literal but LeafKit is running, update will fail. Will initialize context
    /// scope if it does not already exist.
    mutating func setValues(in scope: String = defaultContextScope,
                            to values: [String: LeafDataRepresentable],
                            allLiteral: Bool = false) throws {
        try literalGuard(allLiteral)
        if scope == LKVariable.selfScope && allLiteral { throw err("`self` cannot be literal") }
        try canCreateVariables(scope)
        try checkBlockedVariables(in: scope, .init(values.keys))
        
        let scopeVar = try getScopeKey(scope)
        if contexts[scopeVar]?.literal ?? false {
            if LKConf.isRunning { throw err("\(scope) is a literal scoped context and cannot be updated") }
            assert(allLiteral,
                   "\(scope) already exists as a literal scope - setting values is implicitly literal, not variable")
        }
        if contexts[scopeVar] == nil { contexts[scopeVar] = .init(scopeVar, allLiteral) }
        contexts[scopeVar]!.setValues(values, allLiteral: allLiteral)
    }
    
    /// Update an already existing value and maintain its variable/literal state
    mutating func updateValue(in scope: String = defaultContextScope,
                              at key: String,
                              to value: LeafDataRepresentable) throws {
        let scopeVar = try validateScope(scope)
        guard let isVariable = contexts[scopeVar]![key]?.isVariable else {
            throw err("Value must already be set to update") }
        guard isVariable || !LKConf.isRunning else {
            throw err("Literal context values cannot be updated after LeafKit starts") }
        contexts[scopeVar]![key] = isVariable ? .variable(value) : .literal(value)
    }
    
    /// Lock an entire existing scope and all its contained values as globally literal
    mutating func lockAsLiteral(scope: String) throws {
        try literalGuard()
        let scopeVar = try validateScope(scope)
        contexts[scopeVar]!.setLiteral()
    }
    
    /// Lock an existing value as globally literal
    mutating func lockAsLiteral(in scope: String = defaultContextScope,
                                key: String) throws {
        try literalGuard()
        let scopeVar = try validateScope(scope)
        if self[scopeVar, key] == nil { throw nonExistant(scope, key) }
        contexts[scopeVar]!.setLiteral(key)
    }
    
    /// Cache the current value of `leafData` in context for an existing key
    ///
    /// Only applicable for variable values; locking a scope or value as literal, or declaring as such,
    /// will inherently have cached the value
    mutating func cacheValue(in scope: String = defaultContextScope,
                             at key: String) throws {
        let scopeVar = try validateScope(scope)
        if self[scopeVar, key] == nil { throw nonExistant(scope, key) }
        self[scopeVar, key]!.refresh()
    }
    
    /// All context variable scopes that exist in the object
    var registeredContextScopes: [String] { contexts.keys.compactMap {$0.scope} }
    
    /// All registered contextual objects in the object
    var registeredContextObjects: [(scope: String, object: Any)] {
        var all: [(scope: String, object: Any)] = []
        objects.forEach { (k, v) in v.forEach { if $0.0.contains(.contextual) { all.append((k, $0.1)) } } }
        return all
    }
    
    /// All registered unsafeObject keys
    var registeredUnsafeObjects: [String] { .init(unsafeObjects.keys) }
    
    
    /// Register a Swift object to the context.
    ///
    /// `type: ObjectMode` specifies what ways the object is registered to the context; one or both of:
    ///  * As a context publishing object (must adhere to either `LeafContextPublisher` [preferred] or
    ///     `LeafDataRepresentable` resolving to `LeafData.dictionary`).
    ///  * As a raw object that `LeafUnsafeEntity` objects will have access to during serializing.
    ///
    /// In both cases, `key` represents the access method - for contextual objects, the values it registers
    /// will be published as variables under `$key` scope in Leaf, and for unsafe objects, tags with access
    /// will have `externalObjects[key]` access to the exact object.
    mutating func register(object: Any,
                           toScope key: String,
                           type: ObjectMode = .default) throws {
        precondition(!(type.intersection([.unsafe, .contextual])).isEmpty,
            "Objects to register must be at least one of `unsafe` or `contextual`")
        
        var new = (type, object, Set<String>())
        
        if type.contains(.unsafe) {
            try canOverlay(key, .unsafe)
            unsafeObjects[key] = object
        }
        
        if type.contains(.contextual) {
            guard key.isValidLeafIdentifier else {
                throw err("\(key) is not a valid identifier for a variable scope") }
            try canCreateVariables(key)
            
            let values: [String: LeafDataRepresentable]
            
            if let c = object as? LeafContextPublisher {
                values = c.leafVariables.mapValues { $0.container } }
            else if let data = (object as? LeafDataRepresentable)?.leafData.dictionary {
                values = data }
            else {
                values = [:]
                assertionFailure("A registered external object must be either `LeafContextPublisher` or `LeafDataRepresentable` vending a dictionary when `type` contains `.contextual`") }
            
            if !values.isEmpty, type.contains(.preventOverlay) { new.2.formUnion(values.keys) }
            try setValues(in: key, to: values)
        }
        
        objects[key, default: []].append(new)
    }
    
    mutating func register(generators: [String: LeafDataGenerator],
                           toScope key: String) throws {
        try setValues(in: key, to: generators.mapValues { $0.container })
    }
    
    /// Clear an entire context scope.
    ///
    /// Note that if values were previously registered from an object, they will be removed unconditionally,
    /// and if such reigstered objects prevent overlay or extension, this will not reset that state, so new
    /// values will not be addable.
    mutating func clearContext(scope key: String) throws {
        guard let scope = try? validateScope(key) else { throw err("\(key) is not a valid scope") }
        
        defer { contexts[scope] = nil; if isRootContext { anyLiteral = !literalsOnly.contexts.isEmpty } }
        
        guard LKConf.isRunning else { return }
        guard let ctx = contexts[scope], !ctx.literal else {
            throw err("\(key) is a literal scope - cannot be unset while running") }
        guard ctx.values.allSatisfy({$0.value.isVariable}) else {
            throw err("\(key) has literal values - cannot be unset while running") }
    }

    /// Remove a registered unsafe object, if it exists and is not locked.
    mutating func clearUnsafeObject(key: String) throws {
        try objects[key]?.indices.forEach {
            if objects[key]![$0].0.contains(.unsafe) {
                if objects[key]![$0].0.contains(.preventOverlay) {
                    throw err("\(key) is locked to an object - can't clear") }
                objects[key]![$0].0.remove(.unsafe)
                unsafeObjects.removeValue(forKey: key)
            }
        }
    }
    
    /// Overlay & merge the values of a second context onto a base one.
    ///
    /// When stacking multiple contexts, only a root context may contain literals, so overlaying any
    /// additional context values must be entirely variable (and if conflicts occur in a value where the
    /// underlaying context holds a literal value, will error).
    ///
    /// If a context has options, those set in the second context will always override the lower context's options.
    mutating func overlay(_ secondary: Self) throws {
        guard !secondary.isRootContext else { throw err("Overlaid contexts cannot be root contexts") }
        try secondary.unsafeObjects.forEach {
            try canOverlay($0.key, .unsafe)
            unsafeObjects[$0.key] = $0.value
        }
        try secondary.contexts.forEach { k, v in
            let scope = k.scope!
            try canCreateVariables(scope)
            if contexts[k] == nil { contexts[k] = v }
            else {
                let blockList = blocked(in: scope)
                for key in v.values.keys {
                    if blockList.contains(key) { throw err("\(key) is locked to an object and cannot be overlaid") }
                    if !(contexts[k]![key]?.isVariable ?? true) {
                        throw err("\(k.extend(with: key).terse) is literal in underlaying context; can't override") }
                    contexts[k]![key] = v[key]
                }
            }
        }
        if secondary.options != nil  {
            if options == nil { options = secondary.options }
            else { secondary.options!._storage.forEach { options!._storage.update(with: $0) }  }
        }
    }
}

internal extension LeafRenderer.Context {
    subscript(scope: LKVariable, variable: String) -> LKDataValue? {
        get { contexts[scope]?[variable] }
        set {
            if contexts[scope] == nil {
                if newValue == nil { return }
                contexts[scope] = .init(scope)
            }
            contexts[scope]![variable] = newValue
        }
    }
    
    /// All scope & scoped atomic variables defined by the context
    var allVariables: Set<LKVariable> {
        contexts.values.reduce(into: []) {$0.formUnion($1.allVariables)} }
    
    /// Return a filtered version of the context that holds only literal values for parse stage
    var literalsOnly: Self {
        guard isRootContext else { return .init(isRootContext: false) }
        var contexts = self.contexts
        for (scope, context) in contexts {
            if context.literal { continue }
            context.values.forEach { k, v in if v.isVariable { contexts[scope]![k] = nil } }
            if contexts[scope]!.values.isEmpty { contexts[scope] = nil }
        }
        return .init(isRootContext: true, contexts: contexts)
    }
        
    var timeout: Double {
        if case .timeout(let b) = options?[.timeout] { return b }
        else { return LKROption.timeout } }
    var parseWarningThrows: Bool {
        if case .parseWarningThrows(let b) = options?[.parseWarningThrows] { return b }
        else { return LKROption.parseWarningThrows } }
    var missingVariableThrows: Bool {
        if case .missingVariableThrows(let b) = options?[.missingVariableThrows] { return b }
        else { return LKROption.missingVariableThrows } }
    var grantUnsafeEntityAccess: Bool {
        if case .grantUnsafeEntityAccess(let b) = options?[.grantUnsafeEntityAccess] { return b }
        else { return LKROption.grantUnsafeEntityAccess } }
    var encoding: String.Encoding {
        if case .encoding(let e) = options?[.encoding] { return e }
        else { return LKROption.encoding } }
    var caching: LeafCacheBehavior {
        if case .caching(let c) = options?[.caching] { return c }
        else { return LKROption.caching } }
    var embeddedASTRawLimit: UInt32 {
        if !caching.contains(.limitRawInlines) { return caching.contains(.embedRawInlines) ? .max : 0 }
        if case .embeddedASTRawLimit(let l) = options?[.embeddedASTRawLimit] { return l }
        else { return LKROption.embeddedASTRawLimit }
    }
    var pollingFrequency: Double {
        if !caching.contains(.autoUpdate) { return .infinity }
        if case .pollingFrequency(let d) = options?[.pollingFrequency] { return d }
        else { return LKROption.pollingFrequency }
    }
}

private extension LeafRenderer.Context {
    /// Guard that provided value keys aren't blocked in the scope
    func checkBlockedVariables(in scope: String, _ keys: Set<String>) throws {
        let blockList = keys.intersection(blocked(in: scope))
        if !blockList.isEmpty {
            throw err("\(blockList.description) \(blockList.count == 1 ? "is" : "are") locked to object(s) in context and cannot be overlaid") }
    }
    
    /// Guard that an object can be registered to a scope
    func canOverlay(_ scope: String, _ type: ObjectMode = .bothModes) throws {
        if type.contains(.contextual) { try canCreateVariables(scope) }
        if let x = objects[scope]?.last(where: { !$0.0.intersection(type).isEmpty && $0.0.contains(.preventOverlay) }) {
            throw err("Can't overlay; \(String(describing: x.1)) already registered for `\(scope)`") }
    }
    
    /// Guard that scope isn't locked to an object
    func canCreateVariables(_ scope: String) throws {
        if let x = objects[scope]?.last(where: { $0.0.contains(.lockContextVariables) }) {
            throw err("Can't create variables; \(String(describing: x.1)) locks variables in `\(scope)`") }
    }
    
    /// Validate context is root
    mutating func literalGuard(_ forLiteral: Bool = true) throws {
        guard forLiteral else { return }
        guard isRootContext else { throw err("Cannot set literal values on non-root context") }
        anyLiteral = true
    }
    
    /// Helper error generator
    func nonExistant(_ scope: String, _ key: String? = nil) -> LeafError {
        err("\(scope)\(key != nil ? "[\(key!)]" : "") does not exist in context") }
    
    /// Require that the identifier is valid and scope exists
    func validateScope(_ scope: String) throws -> LKVariable {
        let scopeVar = try getScopeKey(scope)
        guard contexts[scopeVar] != nil else { throw err("\(scopeVar) does not exist in context") }
        return scopeVar
    }
    
    /// Require that the identifier is valid
    func getScopeKey(_ scope: String) throws -> LKVariable {
        guard scope.isValidLeafIdentifier else { throw err(.invalidIdentifier(scope)) }
        return .scope(scope)
    }
    
    /// If a given scope/key in the context is updatable, purely on existential state (variable or literal prior to running)
    func isUpdateable(_ scope: LKVariable, _ key: String) -> Bool {
        if contexts[scope]?.frozen ?? false { return false }
        if contexts[scope]?.literal ?? false && LKConf.isRunning { return false }
        return self[scope, key]?.isVariable ?? true || !LKConf.isRunning
    }
    
    /// List of variable keys that are blocked from being overlaid in the named scope
    func blocked(in scope: String) -> Set<String> {
        objects[scope]?.filter { $0.0.isSuperset(of: [.contextual, .preventOverlay]) }
                       .reduce(into: Set<String>()) { $0.formUnion($1.2) } ?? [] }
}
