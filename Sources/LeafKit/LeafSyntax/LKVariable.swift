
internal struct LKVariable: LKSymbol, Hashable, Equatable {
    let flat: String
    var state: LKVarState
    private let memberStart: UInt8
    private let memberEnd: UInt8
    
    /// Hash equality is purely based on symbol path & whether value or function
    func hash(into hasher: inout Hasher) {
        hasher.combine(flat)
        hasher.combine(isDefine)
    }
    
    static func ==(lhs: Self, rhs: Self) -> Bool { lhs.hashValue == rhs.hashValue }
    
    var isConstant: Bool { state.contains(.constant) }
    var isScope: Bool { memberStart == 0 }
    var isScoped: Bool { state.contains(.scoped) }
    var isSelfScoped: Bool { state.contains(.selfScoped) }
    var isPathed: Bool { state.contains(.pathed) }
    /// Atomic, implicit scope variable - `x` - not `$context.x` or `x.pathed`
    var isAtomic: Bool { !(isScoped || isPathed) }
    var isDefine: Bool { state.contains(.defined) }
    var isBlockDefine: Bool { state.contains(.blockDefine) }
    var isDictionary: Bool { state.contains(.dictionary) }
    var isArray: Bool { state.contains(.array) }
    var isCollection: Bool { isArray || isDictionary }
    
    /// NOTE: Only set in state for `symbols` expressed by a parameter for the purpose of determining if its required
    var isCoalesced: Bool { state.contains(.coalesced) }
    
    var scope: String? {
        !isScoped ? nil
                  : String(flat.dropLast(flat.count - (!isScope ? Int(memberStart) - 1
                                                                : flat.count)).dropFirst()) }
    var member: String? {
        isScope ? nil
                : !isPathed ? String(flat.dropFirst(Int(memberStart)))
                            : String(flat.dropLast(flat.count - Int(memberEnd + 1)).dropFirst(Int(memberStart))) }
    
    var lastPart: String? {
        !isPathed ? nil
                  : String(flat.reversed().split(separator: ".", maxSplits: 1).first!.reversed()) }

    // MARK: - LKSymbol
    var resolved: Bool { false }
    var invariant: Bool { state.contains(.constant) }
    var symbols: Set<LKVariable> { isCoalesced ? [] : [self] }
    func resolve(_ symbols: inout LKVarStack) -> Self { self }
    func evaluate(_ symbols: inout LKVarStack) -> LeafData { symbols.match(self) }

    // MARK: - LKPrintable
    var description: String { flat }
    var short: String { flat }
    var terse: String {
        isDefine ? isBlockDefine ? "define(\(member!))" : "\(member!)()"
                 : !isScoped ? String(flat.dropFirst(2))
                             : isSelfScoped ? "self\(!isScope ? ".\(member!)" : "")"
                                            : flat.replacingOccurrences(of: ":", with: ".") }
    
    static let selfScope = "context"

    init?(_ scope: String? = nil,
          _ member: String? = nil,
          _ path: [String]? = nil) {
        /// Member, scope, path parts must all be valid identifiers. If scope is nil, member must not be empty.
        guard member?.isValidLeafIdentifier ?? true, scope?.isValidLeafIdentifier ?? true,
              member != nil || scope != nil else { return nil }
        if path?.isEmpty == false, !path!.allSatisfy({$0.isValidLeafIdentifier}) { return nil }
        
        var flat = "$\(scope ?? "")"
        self.memberStart = member == nil ? 0 : UInt8(flat.count + 1)
        if let member = member { flat += ":\(member)" }
        self.memberEnd = path == nil ? 0 : UInt8(flat.count - 1)
        if let path = path { flat += path.map { "." + $0 }.joined() }
        self.flat = flat
        self.state = scope == nil ? .atomic : .incoming
        if scope == Self.selfScope { self.state.formUnion(.selfScoped) }
        if path != nil { self.state.formUnion(.pathed) }
    }

    /// Convenience for the `self` scope top-level variable
    static var `self`: Self { .init() }
    /// Convenience for an atomic unscoped variable - DOES NOT validate that string is valid identifier
    static func atomic(_ m: String) -> Self { .init(member: m) }
    /// Convenience for a `Define` identifier - MUST be atomic
    static func define(_ m: String) -> Self { .init(member: m, define: true)}

    static func scope(_ s: String) -> Self { .init(scope: s) }

    /// Remap a variant symbol onto `self` context
    var contextualized: Self { .init(from: self) }
    /// Convenience for unscoped version of self
    var uncontextualized: Self { .init(from: self, newScope: "") }
    /// Return the variable's parent identifier, or nil if a scope level or unscoped member-only
    var parent: Self? { Self.init(child: self) }
    /// Return the scoped, atomic ancestor
    var ancestor: Self { !isPathed ? self : .init(String(flat.dropLast(flat.count - Int(memberEnd) - 1)), memberStart, 0, state.subtracting(.pathed)) }
    /// Extend a symbol with a new identifier - as member or path as appropriate
    func extend(with: String) -> Self { isScope ? .init(from: self, member: with) : .init(from: self, path: with) }
    /// Validate if self is descendent of ancestor
    func isDescendent(of ancestor: Self) -> Bool { flat.hasPrefix(ancestor.flat) && flat.count != ancestor.flat.count }
    var parts: [String] { .init(flat.split(separator: ".").map {String($0)}.dropFirst()) }
        
    /// Generate an atomic unscoped variable
    private init(member: String, define: Bool = false) { self.init("$:\(member)", 2, 0, !define ? .atomic : [.atomic, .defined]) }
    /// Generate a scoped top-level variable
    private init(scope: String = Self.selfScope) { self.init("$\(scope)", 0, 0, .scope(scope)) }

    /// Remap a variant unscoped variable onto an invariant scoped variable
    private init(from: Self, newScope: String = Self.selfScope) {
        var cropped = from.flat
        cropped.removeFirst(2)
        self.init("$\(newScope):\(cropped)", UInt8(newScope.count) + 2,
                  from.isPathed ? from.memberEnd + UInt8(newScope.count) : 0,
                  [.scope(newScope), from.state])
    }
    
    /// Remap a pathed variable up one level
    private init?(child: Self) {
        if child.isAtomic || child.isScope { return nil }
        if !child.isPathed {
            let scope = child.scope!
            self.init(scope, 0, 0, .scope(scope))
        }
        else {
            let end = child.flat.index(before: child.flat.lastIndex(of: .period)!)
            let f = String(child.flat[child.flat.startIndex...end])
            let unpathed = !f.contains(".")
            var state = child.state
            if unpathed { state = state.subtracting(.pathed) }
            self.init(f, child.memberStart, unpathed ? 0 : child.memberEnd, state)
        }
    }

    /// Remap a scoped variable top level variable with a member
    private init(from: Self, member: String) {
        self.init("\(from.flat):\(member)", UInt8(from.flat.count + 1), 0, from.state) }

    /// Remap a  variable with a new path component
    private init(from: Self, path: String) {
        self.init("\(from.flat).\(path)", from.memberStart, !from.isPathed ? UInt8(from.flat.count - 1) : from.memberEnd, from.state.union(.pathed)) }
    
    private init(_ flat: String, _ memberStart: UInt8, _ memberEnd: UInt8, _ state: LKVarState) {
        self.flat = flat
        self.memberStart = memberStart
        self.memberEnd = memberEnd
        self.state = state
    }
}

internal struct LKVarState: OptionSet {
    private(set) var rawValue: UInt16
    init(rawValue: UInt16) { self.rawValue = rawValue }
    
    /// is constant
    static let constant: Self = .init(rawValue: 1 << 0)
    /// has a fixed scope
    static let scoped: Self = .init(rawValue: 1 << 1)
    /// defines a "function" (Define) rather than a value
    static let defined: Self = .init(rawValue: 1 << 2)
    /// is not required at the point of use - should not be set on actual variable, only symbol query of expression
    static let coalesced: Self = .init(rawValue: 1 << 3)
    /// Pathed
    static let pathed: Self = .init(rawValue: 1 << 4)
    /// Context is `self`
    static let selfScoped: Self = .init(rawValue: 1 << 5)
    
    static let array: Self = .init(rawValue: 1 << 6)
    static let dictionary: Self = .init(rawValue: 1 << 7)
    
    /// if `define` - represents block rather than concrete value
    static let blockDefine: Self = .init(rawValue: 1 << 8)
    
    /// Unscoped & atomic
    static let atomic: Self = .init(rawValue: 0)
    /// Scoped & constant
    static let incoming: Self = [.scoped, .constant]
    ///
    static func scope(_ scope: String = LKVariable.selfScope) -> Self {
        scope == LKVariable.selfScope ? [scoped, constant, selfScoped] : incoming
    }
}

extension Set where Element == LKVariable {
    func unsatisfied(by provided: Self) -> Self? {
        if isEmpty { return nil }
        if provided.isEmpty { return self }
        let needed = filter { this in
            if this.isCoalesced { return false }
            if this.isDefine {
                if let other = provided.first(where: {$0 == this}) {
                    return other.isBlockDefine ? !this.isBlockDefine : false
                } else { return true }
            }
            if this.isScoped { return !provided.contains(this) }
            return provided.contains(this) ? false : !provided.contains(this.contextualized)
        }
        return needed.isEmpty ? nil : needed
    }
    
    func unsatisfied(by ctx: LeafContext) -> Self? {
        unsatisfied(by: ctx.contexts.isEmpty ? []
        : ctx.contexts.values.reduce(into: []) { $0.formUnion($1.allVariables) })
    }
    
    /// Defines in the provided set that match, but are block defines and not param defines
    func badDefineMatches(in provided: Self) -> Self? {
        let mismatches = paramDefines.intersection(provided.filter({$0.isBlockDefine}))
        return mismatches.isEmpty ? nil : mismatches
    }
    
    ///
    var variables: Self { filter {!$0.isDefine} }
    /// All defines are inherently block and param defines
    var blockDefines: Self { filter {$0.isDefine} }
    /// Param defines are any non-block define
    var paramDefines: Self { filter {$0.isDefine && !$0.isBlockDefine} }

    var coalesced: Self { filter {$0.isCoalesced} }
    var unCoalesced: Self { filter {!$0.isCoalesced} }
}
