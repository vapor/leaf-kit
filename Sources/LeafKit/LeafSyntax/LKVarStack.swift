/// Stack of currently defined overlays of `LKVarTable`
///
/// IDs: All uncontextualized variable names defined *at this level*
/// Vars: Any variables defined *at this level* - when value is assigned, go down to level at *which* it was
///     last defined
internal struct LKVarStack {
    var context: LeafRenderer.Context
    var stack: [(ids: Set<String>, vars: LKVarTablePtr)]
    
    /// Locate the `LKVariable` in the stack, if possible
    mutating func match(_ variable: LKVariable) -> LKData? {
        var err: LKData { .error(internal: "No value for \(variable.terse) in context") }
        
        if variable.isScoped { return context.get(variable) }
        var depth = stack.count - 1
        while depth >= 0 {
            if let x = stack[depth].vars.match(variable) { return x }
            depth -= 1
        }
        let atomic = variable.member!
        /// Already contextualized
        if stack[0].ids.contains(atomic) { return err }
        let root = variable.ancestor.contextualized
        if let found = context.get(root) {
            if found.errored { return found }
            stack[0].ids.insert(atomic)
            stack[0].vars.pointee[variable.ancestor] = found
            return stack[0].vars.match(variable)
        } else { return err }
    }
    
    /// Update a non-scoped/pathed variable that explicitly exists, or create at specified level if an atomic
    /// Default atomic creation level is the topmost stack (nil)
    mutating func update(_ variable: LKVariable,
                         _ value: LKData,
                         createAt level: Int? = nil) {
        defer { stack[depth].vars.pointee[variable] = value }
        var depth = stack.count - 1
        repeat {
            if let found = stack[depth].vars.match(variable) {
                if found.celf == .dictionary {
                    stack[depth].vars.dropDescendents(of: variable) }
                return
            }
            depth -= 1
        } while depth > 0
        let level = level ?? stack.count - 1
        if variable.isAtomic, (0...stack.count-1).contains(level) {
            depth = level
            stack[depth].ids.insert(variable.member!)
            return
        }
        
        __MajorBug("Shouldn't reach this")
    }
    
    /// Explicitly create a non-contextualized variable at the current stack depth
    func create(_ variable: LKVariable, _ value: LKData?) {
        let value = value != nil ? value : .trueNil
        stack[stack.count - 1].vars.pointee[variable] = value
    }
}

