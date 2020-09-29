/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKData]
/// UnsafeMutablePointer to `[LKVariable: LKData]`
internal typealias LKVarTablePtr = UnsafeMutablePointer<LKVarTable>

internal extension LKVarTablePtr {
    /// Locate the `LKVariable` in the table, if possible. Never use with scoped variable.
    ///
    /// If variable is pathed and the root object exists, auto-expands the variable path into the table to retain
    /// for future accession.
    func match(_ variable: LKVariable) -> LKData? {
        func err(_ a: LKVariable) -> LKData {
            return .error(internal: "\(a.terse) is not a dictionary; \(variable.terse) is invalid") }
        
        /// If table holds variable or variable is atomic, immediately return result or nil
        guard !pointee.keys.contains(variable),
              variable.isPathed else { return pointee[variable] }
        /// Root ancestor must be set to check this scope
        guard let member = variable.member,
              let ancestor = pointee[.atomic(member)] else { return nil }
        if ancestor.celf != .dictionary { return err(.atomic(member)) }
        /// Go up until pathed ancestor is set
        var last = variable
        var parts = [variable.lastPart!]
        var found: (LKVariable, LeafData)? = nil
        while let parent = last.parent, parent.isPathed {
            if let f = pointee[parent] { found = (parent, f); break }
            else { parts.append(parent.lastPart!); last = parent; continue }
        }
        while let part = parts.last {
            guard let here = found!.1.dictionary else { return err(found!.0) }
            guard let value = here[part] else { return .error("\(found!.0.terse) has no member \(part)") }
            let pathed = found!.0.extend(with: part)
            pointee[pathed] = value
            found = (pathed, value)
            parts.removeLast()
        }
        return pointee[variable]
    }
    
    func dropDescendents(of variable: LKVariable) {
        pointee.keys.forEach { if $0.isDescendent(of: variable) { pointee[$0] = nil } }
    }
}
