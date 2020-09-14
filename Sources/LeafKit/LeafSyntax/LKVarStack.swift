/// Stack of currently defined overlays of `LKVarTable`
///
/// IDs: All uncontextualized variable names defined *at this level*
/// Vars: Any variables defined *at this level* - when value is assigned, go down to level at *which* it was
///     last defined
internal typealias LKVarStack = [(ids: Set<String>,
                                  vars: LKVarTablePtr,
                                  unsafe: ExternalObjects?)]

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

