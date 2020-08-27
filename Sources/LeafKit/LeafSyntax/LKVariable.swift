/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKData]

internal typealias LKVarStack = [(ids: Set<String>, vars: LKVarTablePointer)]
/// UnsafeMutablePointer to `[LKVariable: LKData]`
internal typealias LKVarTablePointer = UnsafeMutablePointer<LKVarTable>

internal extension LKVarTable {
    /// Locate the `LKVariable` in the table, if possible
    func match(_ variable: LKVariable, contextualize: Bool = true) -> LKData? {
        // Immediate catch if table holds exact identifier
        guard !keys.contains(variable) else { return self[variable] }
        // If variable has explicit scope, no way to contextualize - no hit
        if variable.scope != nil || !contextualize { return nil }
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
    
    /// Assumes table is prefiltered for valid identifiers
    init(_ table: [String: LeafDataRepresentable], _ base: LKVariable? = nil) {
        self.init(uniqueKeysWithValues: table.map {(base != nil ? base!.extend(with: $0.key): .atomic($0.key), $0.value.leafData)})
    }
    
    /// Assumes table is prefiltered for valid identifiers
    init(_ table: [String: LKData], _ base: LKVariable? = nil) {
        self.init(uniqueKeysWithValues: table.map {(base != nil ? base!.extend(with: $0.key) : .atomic($0.key), $0.value)})
    }
}

internal extension LKVarStack {
    /// Locate the `LKVariable` in the stack, if possible
    func match(_ variable: LKVariable, contextualize: Bool = true) -> LKData? {
        var depth = count - 1
        while depth >= 0 {
            if let x = self[depth].vars.pointee[variable] { return x }
            if depth > 0 { depth -= 1; continue }
            return self[depth].vars.pointee.match(variable, contextualize: contextualize)
        }
        return nil
    }
    
    /// Update a non-scoped variable that explicitly exists, or if contextualized root exists, create & update at base
    func update(_ variable: LKVariable, _ value: LKData) {
        var depth = count - 1
        repeat {
            if self[depth].vars.pointee[variable] != nil {
                self[depth].vars.pointee[variable] = value
                return
            }
            depth -= depth > 0 ? 1 : 0
        } while depth >= 0
        if self[0].vars.pointee[variable.contextualized] != nil {
            self[0].vars.pointee[variable] = value
        }
    }
    
    /// Explicitly create a non-contextualized variable at the current stack depth
    func create(_ variable: LKVariable, _ value: LKData?) {
        let value = value != nil ? value : .trueNil
        self[count - 1].vars.pointee[variable] = value
    }
}


internal struct LKVariable: LKSymbol, Hashable {
    let flat: String
    private let memberStart: UInt8
    private let memberEnd: UInt8
    /// Branching behavior - Variable does not refer to a concrete LeafData but a jump point to a `Define`
    let define: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(flat)
        hasher.combine(define)
    }
    
    var atomic: Bool { memberStart == 2 && memberEnd == 0 }
    var pathed: Bool { memberEnd != 0 }

    var scope: String? {
        memberStart == 2 ? nil : String(flat.dropLast(flat.count - (memberStart != 0 ? Int(memberStart) - 1 : flat.count)).dropFirst()) }
    var member: String? {
        memberStart == 0 ? nil : memberEnd == 0 ? String(flat.dropFirst(Int(memberStart)))
                                                : String(flat.dropLast(flat.count - Int(memberEnd)).dropFirst(Int(memberStart))) }

    // MARK: - LKSymbol
    let resolved: Bool = false
    var invariant: Bool { memberStart == 0 || memberStart > 2 }
    var symbols: Set<LKVariable> { [self] }
    func resolve(_ symbols: LKVarStack) -> Self { self }
    func evaluate(_ symbols: LKVarStack) -> LeafData { symbols.match(self) ?? .trueNil }

    // MARK: - LKPrintable
    var description: String { flat }
    var short: String { flat }
    var terse: String {
        memberStart == 2 ? String(flat.dropFirst(2))
                         : scope == Self.selfScope ? "self\(member != nil ? ".\(member!)" : "")"
                                                   : flat
    }
    
    static let selfScope = "context"

    init?(_ scope: String? = nil,
          _ member: String,
          _ path: [String]? = nil) {
        /// Member, scope, path parts must all be valid identifiers. If scope is nil, member must not be empty.
        guard member.isValidIdentifier || member.isEmpty,
              scope?.isValidIdentifier ?? true else { return nil }
        if scope == nil && member.isEmpty { return nil }
        if path?.isEmpty == false, !path!.allSatisfy({$0.isValidIdentifier}) { return nil }
        
        var flat = "$\(scope ?? "")"
        self.memberStart = member.isEmpty ? 0 : UInt8(flat.count + 1)
        if !member.isEmpty { flat += ":\(member)" }
        self.memberEnd = path == nil ? 0 : UInt8(flat.count - 1)
        if let path = path { flat += path.map { "." + $0 }.joined() }
        self.flat = flat
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
    /// Convenience for unscoped version of self
    var uncontextualized: Self { .init(from: self, newScope: "") }
    /// Return the variable's parent identifier, or nil if a scope level or unscoped member-only
    var parent: Self? { Self.init(child: self) }
    /// Return the scoped, atomic ancestor
    var ancestor: Self { !pathed ? self : .init(String(flat.dropLast(flat.count - Int(memberEnd) - 1)), memberStart, 0) }
    /// Extend a symbol with a new identifier - as member or path as appropriate
    func extend(with: String) -> Self { memberStart == 0 ? .init(from: self, member: with) : .init(from: self, path: with) }
    /// Validate if self is descendent of ancestor
    func isDescendent(of ancestor: Self) -> Bool { flat.hasPrefix(ancestor.flat) && flat.count > ancestor.flat.count }
    
    /// Generate an atomic unscoped variable
    private init(member: String, define: Bool = false) { self.init("$:\(member)", 2, 0, define) }
    /// Generate a scoped top-level variable
    private init(scope: String = Self.selfScope) { self.init("$\(scope)", 0, 0) }

    /// Remap a variant unscoped variable onto an invariant scoped variable
    private init(from: Self, newScope: String = Self.selfScope) {
        var cropped = from.flat
        cropped.removeFirst(2)
        self.init("$\(newScope):\(cropped)", UInt8(newScope.count) + 2,
                  from.memberEnd != 0 ? from.memberEnd + UInt8(newScope.count) : 0)
    }
    
    /// Remap a pathed variable up one level
    private init?(child: Self) {
        if child.atomic || (child.memberStart == 0) { return nil }
        if !child.pathed {
            self.init(child.scope!, 0, 0) }
        else {
            let unpathed = child.flat.filter({$0 == .period}).count == 1
            let end = child.flat.lastIndex(of: .period)!
            let f = String(child.flat[child.flat.startIndex...end])
            self.init(f, child.memberStart, unpathed ? 0 : child.memberEnd) }
    }

    /// Remap a scoped variable top level variable with a member
    private init(from: Self, member: String) {
        self.init("\(from.flat):\(member)", UInt8(from.flat.count + 1), 0) }

    /// Remap a  variable with a new path component
    private init(from: Self, path: String) {
        self.init("\(from.flat).\(path)", from.memberStart, from.memberEnd == 0 ? UInt8(from.flat.count - 1) : from.memberEnd) }
    
    private init(_ flat: String, _ memberStart: UInt8, _ memberEnd: UInt8, _ define: Bool = false) {
        self.flat = flat
        self.memberStart = memberStart
        self.memberEnd = memberEnd
        self.define = define
    }
}
