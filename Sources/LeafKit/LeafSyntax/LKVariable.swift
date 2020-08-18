// MARK: Subject to change prior to 1.0.0 release
// MARK: -

internal struct LKVariable: LKSymbol, Hashable {
    let flat: String
    private let memberStart: Int
    private let memberEnd: Int

    var atomic: Bool { memberStart == 2 && memberEnd == -1 }
    var pathed: Bool { memberEnd != -1 }

    var scope: String? {
        memberStart == 2 ? nil : String(flat.dropLast(flat.count - memberStart - 1).dropFirst())
    }
    var member: String? {
        if memberStart == -1 { return nil }
        if memberEnd == -1 { return String(flat.dropFirst(memberStart)) }
        return String(flat.dropLast(flat.count - memberEnd - 1).dropFirst(memberStart))
    }

    // MARK: - LKSymbol
    let resolved: Bool = false
    var invariant: Bool { memberStart == -1 || memberStart > 2 }
    var symbols: Set<LKVariable> { [self] }
    func resolve(_ symbols: LKVarTablePointer) -> Self { self }
    func evaluate(_ symbols: LKVarTablePointer) -> LeafData {
        symbols.pointee.match(self) ?? .trueNil
    }

    // MARK: - LKPrintable
    var description: String { flat }
    var short: String { flat }

    static let selfScope = "context"

    init?(_ scope: String? = nil,
          _ member: String,
          _ path: [String]? = nil) {
        guard member.isValidIdentifier || member.isEmpty,
              scope?.isValidIdentifier ?? true else { return nil }
        if scope == nil && member.isEmpty { return nil }
        var flat = "$\(scope ?? "")"
        self.memberStart = member.isEmpty ? -1 : flat.count + 1
        let memberEnd: Int
        if !member.isEmpty { flat += ":\(member)" }
        if let path = path, path.allSatisfy({$0.isValidIdentifier}),
           !path.isEmpty {
            memberEnd = flat.count - 1
            flat += path.map { "." + $0 }.joined()
        } else if path == nil { memberEnd = -1 } else { return nil }
        self.flat = flat
        self.memberEnd = memberEnd
    }

    /// Convenience for the `self` scope top-level variable
    static var `self`: Self { .init() }
    /// Convenience for an atomic unscoped variable - DOES NOT validate that string is valid identifier
    static func atomic(_ m: String) -> Self { .init(member: m) }

    /// Remap a variant symbol onto `self` context
    var contextualized: Self { .init(from: self) }
    /// Return the variable's parent identifier, or nil if a scope level or unscoped member-only
    var parent: Self? { Self.init(child: self) }
    /// Extend a symbol with a new identifier - as member or path as appropriate
    func extend(with: String) -> Self {
        if memberStart == -1 { return .init(from: self, member: with)}
        return .init(from: self, path: with)
    }
    /// Validate if self is descendent of ancestor
    func isDescendent(of ancestor: Self) -> Bool { flat.hasPrefix(ancestor.flat) }

    /// Generate an atomic unscoped variable
    private init(member: String) {
        self.flat = "$:\(member)"
        self.memberStart = 2
        self.memberEnd = -1
    }

    /// Generate a scoped top-level variable
    private init(scope: String = Self.selfScope) {
        self.flat = "$\(scope)"
        self.memberStart = -1
        self.memberEnd = -1
    }

    /// Remap a variant unscoped variable onto an invariant scoped variable
    private init(from: Self, newScope: String = Self.selfScope) {
        var cropped = from.flat
        cropped.removeFirst(2)
        self.flat = "$\(newScope):\(cropped)"
        self.memberStart = newScope.count + 1
        self.memberEnd = from.memberEnd != -1 ? from.memberEnd + newScope.count : -1
    }
    
    /// Remap a pathed variable up one level
    private init?(child: Self) {
        if child.atomic || (child.memberStart == -1) { return nil }
        if !child.pathed {
            self.flat = child.scope!
            self.memberStart = -1
            self.memberEnd = -1
        } else {
            let unpathed = child.flat.filter({$0 == .period}).count == 1
            self.memberStart = child.memberStart
            self.memberEnd = unpathed ? -1 : child.memberEnd
            let end = child.flat.lastIndex(of: .period)!
            self.flat = String(child.flat[child.flat.startIndex...end])
        }
    }

    /// Remap a scoped variable top level variable with a member
    private init(from: Self, member: String) {
        self.flat = "\(from.flat):\(member)"
        self.memberStart = from.flat.count
        self.memberEnd = -1
    }

    /// Remap a  variable with a new path component
    private init(from: Self, path: String) {
        self.flat = "\(from.flat).\(path)"
        self.memberStart = from.memberStart
        self.memberEnd = from.memberEnd == -1 ? from.flat.count - 1 : from.memberEnd
    }
}
