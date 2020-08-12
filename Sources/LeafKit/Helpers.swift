// MARK: - Public Type Shorthands

public typealias LeafASTKey = LeafAST.Key
public typealias LeafASTInfo = LeafAST.Info
public typealias LeafASTTouch = LeafAST.Touch

// MARK: - Internal Type Shorthands

internal typealias LKConf = LeafConfiguration
internal typealias ELF = EventLoopFuture
/// `Leaf(Kit)Data`
internal typealias LKD = LeafData
/// `Leaf(Kit)DataType`
internal typealias LKDT = LeafDataType
/// `[LKParameter]` - no special bounds enforced, used to pass to `LKTuple` which validates
internal typealias LKParams = [LKParameter]
/// A `LKVarTable` provides a Dictionary of concrete `LeafData` available for a symbolic key
internal typealias LKVarTable = [LKVariable: LKD]

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
    func match(_ variable: LKVariable) -> LKD {
        keys.contains(variable) ? self[variable]!
                                : self[variable.contextualized] ?? .trueNil
    }
}
