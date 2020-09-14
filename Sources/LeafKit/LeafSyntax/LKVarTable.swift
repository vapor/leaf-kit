/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKData]
/// UnsafeMutablePointer to `[LKVariable: LKData]`
internal typealias LKVarTablePtr = UnsafeMutablePointer<LKVarTable>

internal extension LKVarTable {
    /// Locate the `LKVariable` in the table, if possible
    func match(_ variable: LKVariable, contextualize: Bool = true) -> LKData? {
        // Immediate catch if table holds exact identifier
        guard !keys.contains(variable) else { return self[variable] }
        // If variable has explicit scope, no way to contextualize - no hit
        if variable.isScoped || !contextualize { return nil }
        // If atomic, immediately check contextualized self.member
        if variable.isAtomic { return self[variable.contextualized] }
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
