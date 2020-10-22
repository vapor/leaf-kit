// MARK: - Public Implementation

public extension LeafRenderer.Option {
    /// The current global configuration for rendering options
    static var allCases: [Self] {[
        .timeout(Self.$timeout._unsafeValue),
        .missingVariableThrows(Self.$missingVariableThrows._unsafeValue),
        .grantUnsafeEntityAccess(Self.$grantUnsafeEntityAccess._unsafeValue),
        .encoding(Self.$encoding._unsafeValue),
        .caching(Self.$caching._unsafeValue),
        .embeddedASTRawLimit(Self.$embeddedASTRawLimit._unsafeValue)        
    ]}
    
    func hash(into hasher: inout Hasher) { hasher.combine(celf) }
    static func ==(lhs: Self, rhs: Self) -> Bool { lhs.celf == rhs.celf }
}

public extension LeafRenderer.Options {
    /// All global settings for options on `LeafRenderer`
    static var globalSettings: Self { .init(LeafRenderer.Option.allCases) }
    
    init(_ elements: [LeafRenderer.Option]) {
        self._storage = elements.reduce(into: []) {
            if !$0.contains($1) && $1.valid == true { $0.update(with: $1) } }
    }
    
    init(arrayLiteral elements: LeafRenderer.Option...) { self.init(elements) }
    
    @discardableResult
    mutating func update(_ option: LeafRenderer.Option) -> Bool {
        let result = option.valid
        if result == false { return false }
        if result == nil { _storage.remove(option) } else { _storage.update(with: option) }
        return true
    }
    
    mutating func unset(_ option: LeafRenderer.Option.Case) {
        if let x = _storage.first(where: {$0.celf == option}) { _storage.remove(x) } }
}

// MARK: - Internal Implementation

internal extension LeafRenderer.Option {
    var celf: Case {
        switch self {
            case .timeout                 : return .timeout
            case .missingVariableThrows   : return .missingVariableThrows
            case .grantUnsafeEntityAccess : return .grantUnsafeEntityAccess
            case .encoding                : return .encoding
            case .caching                 : return .caching
            case .embeddedASTRawLimit     : return .embeddedASTRawLimit
        }
    }
    
    /// Validate that the local setting for an option is acceptable or ignorable (matches global setting)
    var valid: Bool? {
        switch self {
            case .missingVariableThrows(let b)   : return Self.$missingVariableThrows.validate(b)
            case .grantUnsafeEntityAccess(let b) : return Self.$grantUnsafeEntityAccess.validate(b)
            case .timeout(let t)                 : return Self.$timeout.validate(t)
            case .encoding(let e)                : return Self.$encoding.validate(e)
            case .caching(let c)                 : return Self.$caching.validate(c)
            case .embeddedASTRawLimit(let l)     : return Self.$embeddedASTRawLimit.validate(l)
        }
    }
}

internal extension LeafRenderer.Options {
    subscript(key: LeafRenderer.Option.Case) -> LeafRenderer.Option? {
        _storage.first(where: {$0.celf == key}) }
}
