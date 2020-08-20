/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKData]

internal typealias LKVarStack = [(ids: Set<String>, vars: LKVarTablePointer)]
/// UnsafeMutablePointer to `[LKVariable: LKData]`
internal typealias LKVarTablePointer = UnsafeMutablePointer<LKVarTable>

internal extension LKVarTable {
    /// Locate the `LKVariable` in the table, if possible
    func match(_ variable: LKVariable) -> LKData? {
        // Immediate catch if table holds exact identifier
        guard !keys.contains(variable) else { return self[variable] }
        // If variable has explicit scope, no way to contextualize - no hit
        if variable.scope != nil { return nil }
        // If atomic, immediately check contextualized self.member
        if variable.atomic { return self[variable.contextualized] }
        // Ensure no ancestor of the identifier is set before contextualizing
        var parent = variable.parent
        repeat {
            if self[parent!] != nil { return nil }
            parent = parent!.parent
        } while parent != nil
        return self[variable.contextualized]
    }
}

internal extension LKVarStack {
    /// Locate the `LKVariable` in the stack, if possible
    func match(_ variable: LKVariable) -> LKData? {
        var depth = count - 1
        repeat {
            if let x = self[depth].vars.pointee[variable] { return x }
            if depth > 0 { depth -= 1; continue }
            return self[depth].vars.pointee.match(variable)
        } while depth >= 0
        return nil
    }
}


internal struct LKVariable: LKSymbol, Hashable {
    let flat: String
    private let memberStart: Int
    private let memberEnd: Int
    private let define: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(flat)
        hasher.combine(define)
    }

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
    func resolve(_ symbols: LKVarStack) -> Self { self }
    func evaluate(_ symbols: LKVarStack) -> LeafData { symbols.match(self) ?? .trueNil }

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
        self.define = false
    }

    /// Convenience for the `self` scope top-level variable
    static var `self`: Self { .init() }
    /// Convenience for an atomic unscoped variable - DOES NOT validate that string is valid identifier
    static func atomic(_ m: String) -> Self { .init(member: m) }
    /// Convenience for a `Define` identifier - MUST be atomic
    static func define(_ m: String) -> Self { .init(member: m, define: true)}

    /// Remap a variant symbol onto `self` context
    var contextualized: Self { .init(from: self) }
    /// Return the variable's parent identifier, or nil if a scope level or unscoped member-only
    var parent: Self? { Self.init(child: self) }
    /// Extend a symbol with a new identifier - as member or path as appropriate
    func extend(with: String) -> Self { memberStart == -1 ? .init(from: self, member: with) : .init(from: self, path: with) }
    /// Validate if self is descendent of ancestor
    func isDescendent(of ancestor: Self) -> Bool { flat.hasPrefix(ancestor.flat) }

    /// Generate an atomic unscoped variable
    private init(member: String, define: Bool = false) {
        self.flat = "$:\(member)"
        self.memberStart = 2
        self.memberEnd = -1
        self.define = define
    }

    /// Generate a scoped top-level variable
    private init(scope: String = Self.selfScope) {
        self.flat = "$\(scope)"
        self.memberStart = -1
        self.memberEnd = -1
        self.define = false
    }

    /// Remap a variant unscoped variable onto an invariant scoped variable
    private init(from: Self, newScope: String = Self.selfScope) {
        var cropped = from.flat
        cropped.removeFirst(2)
        self.flat = "$\(newScope):\(cropped)"
        self.memberStart = newScope.count + 2
        self.memberEnd = from.memberEnd != -1 ? from.memberEnd + newScope.count : -1
        self.define = false
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
        self.define = false
    }

    /// Remap a scoped variable top level variable with a member
    private init(from: Self, member: String) {
        self.flat = "\(from.flat):\(member)"
        self.memberStart = from.flat.count + 1
        self.memberEnd = -1
        self.define = false
    }

    /// Remap a  variable with a new path component
    private init(from: Self, path: String) {
        self.flat = "\(from.flat).\(path)"
        self.memberStart = from.memberStart
        self.memberEnd = from.memberEnd == -1 ? from.flat.count - 1 : from.memberEnd
        self.define = false
    }
}
