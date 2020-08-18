// MARK: - Public Type Shorthands

// MARK: - LeafAST
public typealias LeafASTKey = LeafAST.Key
public typealias LeafASTInfo = LeafAST.Info
public typealias LeafASTTouch = LeafAST.Touch

// MARK: - LeafFunction, *Method, *Block, *Raw
public typealias CallParameters = [LeafCallParameter]
public typealias CallValues = LeafCallValues

// MARK: - LeafBook, *Raw
public typealias ParseSignatures = [String: [LeafParseParameter]]

// MARK: - Internal Type Shorthands

internal typealias LKConf = LeafConfiguration
internal typealias ELF = EventLoopFuture
/// `Leaf(Kit)Data`
internal typealias LKData = LeafData
/// `Leaf(Kit)DataType`
internal typealias LKDType = LeafDataType
/// `[LKParameter]` - no special bounds enforced, used to pass to `LKTuple` which validates
internal typealias LKParams = [LKParameter]
/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKData]
internal typealias LKVarTablePointer = UnsafeMutablePointer<LKVarTable>

// MARK: - Internal Helper Extensions

internal extension Comparable {
    /// Conditional shorthand for lhs = max(lhs, rhs)
    mutating func maxAssign(_ rhs: Self) { self = max(self, rhs) }
}

internal extension Double {
    /// Convenience for formatting Double to a s/ms/µs String
    var formatSeconds: String {
        let abs = self.magnitude
        if abs * 10 > 1 { return String(format: "%.3f%", abs) + " s"}
        if abs * 1_000 > 1 { return String(format: "%.3f%", abs * 1_000) + " ms" }
        return String(format: "%.3f%", abs * 1_000_000) + " µs"
    }
}

internal extension Int {
    /// Convenience for formatting Ints to a B/kB/mB String
    var formatBytes: String { "\(signum() == -1 ? "-" : "")\(magnitude.formatBytes)" }
}

internal extension UnsignedInteger {
    /// Convenience for formatting UInts to a B/kB/mB String
    var formatBytes: String {
        if self > 1024 * 512 { return String(format: "%.2fmB", Double(self)/1024.0/1024.0) }
        if self > 512 { return String(format: "%.2fkB", Double(self)/1024.0) }
        return "\(self)B"
    }
}

internal extension LKVarTable {
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
