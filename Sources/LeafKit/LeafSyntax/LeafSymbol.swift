// MARK: Subject to change prior to 1.0.0 release
// MARK: -


internal struct LeafVariable: LeafSymbol, Hashable {
    internal private(set) var flat: String
    private var memberStart: Int = -1
    private var memberEnd: Int = -1
    
    internal var atomic: Bool { memberStart == 2 && memberEnd == -1 }
    internal var pathed: Bool { memberEnd != -1 }
    
    internal var scope: String? {
        if atomic { return nil }
        return String(flat.dropLast(flat.count - memberStart - 1).dropFirst())
    }
    internal var member: String? {
        if memberStart == -1 { return nil }
        if memberEnd == -1 { return String(flat.dropFirst(memberStart)) }
        return String(flat.dropLast(flat.count - memberEnd - 1).dropFirst(memberStart))
    }
    
    // MARK: - LeafSymbol
    internal var resolved: Bool { false }
    internal var invariant: Bool { memberStart == -1 || memberStart > 2 }
    internal var symbols: Set<LeafVariable> { [self] }
    func resolve(_ symbols: SymbolMap) -> Self { self }
    func evaluate(_ symbols: SymbolMap) -> LeafData {
        symbols.match(self)
        
    }
    
    // MARK: - SymbolPrintable
    public var description: String { flat }
    internal var short: String { flat }
        
    static let selfScope = "context"
    
    internal init?(_ scope: String? = nil,
                   _ member: String,
                   _ path: [String]? = nil) {
        guard member.isValidIdentifier || member.isEmpty,
              scope?.isValidIdentifier ?? true else { return nil }
        if scope == nil && member.isEmpty { return nil }
        self.flat = "$\(scope ?? "")"
        if !member.isEmpty {
            self.memberStart = self.flat.count + 1
            self.flat += ":\(member)"
        }
        if let path = path, !path.isEmpty,
           path.allSatisfy({$0.isValidIdentifier}) {
            self.memberEnd = self.flat.count - 1
            self.flat += path.map { "." + $0 }.joined()
        } else if path != nil { return nil }
    }
    
    /// Convenience for the `self` scope top-level variable
    internal static var `self`: Self { .init() }
    /// Convenience for an atomic unscoped variable - DOES NOT validate that string is valid identifier
    internal static func atomic(_ m: String) -> Self { .init(member: m) }
    
    /// Remap a variant symbol onto `self` context
    internal var contextualized: Self { .init(from: self) }
    /// Extend a symbol with a new identifier - as member or path as appropriate
    internal func extend(with: String) -> Self {
        if memberStart == -1 { return .init(from: self, member: with)}
        return .init(from: self, path: with)
    }
    
    /// Generate an atomic unscoped variable
    private init(member: String) {
        self.flat = "$:\(member)"
        self.memberStart = 2
    }
    
    /// Generate a scoped top-level variable
    private init(scope: String = Self.selfScope) {
        self.flat = "$\(scope)"
    }
    
    /// Remap a variant unscoped variable onto an invariant scoped variable
    private init(from: Self, newScope: String = Self.selfScope) {
        var cropped = from.flat
        cropped.removeFirst(2)
        self.flat = "$\(newScope):\(cropped)"
        self.memberStart = newScope.count + 1
        if from.memberEnd != -1 { self.memberEnd = from.memberEnd + newScope.count }
    }
    
    /// Remap a scoped variable top level variable with a member
    private init(from: Self, member: String) {
        self.flat = "\(from.flat):\(member)"
        self.memberStart = from.flat.count
    }
    
    
    /// Remap a  variable with a new path component
    private init(from: Self, path: String) {
        self.flat = "\(from.flat).\(path)"
        self.memberStart = from.memberStart
        self.memberEnd = from.memberEnd == -1 ? from.flat.count - 1 : from.memberEnd
    }
}
