// MARK: - Public Implementation

public extension LeafRenderer.Option {
    static var allCases: [Self] {[
        .timeout(LKRContext.$timeout._unsafeValue),
        .missingVariableThrows(LKRContext.$missingVariableThrows._unsafeValue),
        .grantUnsafeEntityAccess(LKRContext.$grantUnsafeEntityAccess._unsafeValue),
        .cacheBypass(LKRContext.$cacheBypass._unsafeValue)
    ]}
    
    func hash(into hasher: inout Hasher) { hasher.combine(celf) }
    static func ==(lhs: Self, rhs: Self) -> Bool { lhs.celf == rhs.celf }
}

public extension LeafRenderer.Options {
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
            case .cacheBypass             : return .cacheBypass
        }
    }
    
    var valid: Bool? {
        switch self {
            case .missingVariableThrows(let b)   : return LKRContext.$missingVariableThrows.validate(b)
            case .grantUnsafeEntityAccess(let b) : return LKRContext.$grantUnsafeEntityAccess.validate(b)
            case .cacheBypass(let b)             : return LKRContext.$cacheBypass.validate(b)
            case .timeout(let t)                 : return LKRContext.$timeout.validate(t)
        }
    }
}

internal extension LeafRenderer.Options {
    subscript(key: LeafRenderer.Option.Case) -> LeafRenderer.Option? {
        _storage.first(where: {$0.celf == key}) }
}
