import Foundation

/// Internal conveniences on native Swift types/protocols

internal extension Comparable {
    /// Conditional shorthand for lhs = max(lhs, rhs)
    mutating func maxAssign(_ rhs: Self) { self = max(self, rhs) }
}

internal extension Double {
    /// Convenience for formatting Double to a s/ms/µs String
    func formatSeconds(places: Int = 2) -> String {
        let abs = self.magnitude
        if abs * 10 > 1 { return String(format: "%.\(places)f%", abs) + " s"}
        if abs * 1_000 > 1 { return String(format: "%.\(places)f%", abs * 1_000) + " ms" }
        return String(format: "%.\(places)f%", abs * 1_000_000) + " µs"
    }
}

internal extension Int {
    /// Convenience for formatting Ints to a B/kB/mB String
    func formatBytes(places: Int = 2) -> String { "\(signum() == -1 ? "-" : "")\(magnitude.formatBytes(places: places))" }
}

internal extension UnsignedInteger {
    /// Convenience for formatting UInts to a B/kB/mB String
    func formatBytes(places: Int = 2) -> String {
        if self > 1024 * 1024 * 512 { return String(format: "%.\(places)fGB", Double(self)/1024.0/1024.0/1024.0) }
        if self > 1024 * 512 { return String(format: "%.\(places)fMB", Double(self)/1024.0/1024.0) }
        if self > 512 { return String(format: "%.\(places)fKB", Double(self)/1024.0) }
        return "\(self)B"
    }
}

internal extension CaseIterable {
    static var terse: String { "[\(Self.allCases.map {"\($0)"}.joined(separator: ", "))]" }
}

extension Array: LKPrintable where Element == LeafCallParameter {
    var description: String { short }
    var short: String  { "(\(map {$0.short}.joined(separator: ", ")))" }
}

/// Tired of writing `distance(to: ...`
infix operator +->

extension Date {
    /// Tired of writing `distance(to: ...`
    static func +->(_ from: Self, _ to: Self) -> Double {
        from.timeIntervalSinceReferenceDate.distance(to: to.timeIntervalSinceReferenceDate)
    }
}
