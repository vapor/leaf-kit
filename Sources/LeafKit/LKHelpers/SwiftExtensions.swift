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
infix operator +-> : AdditionPrecedence

internal extension Date {
    /// Tired of writing `distance(to: ...`
    static func +->(_ from: Self, _ to: Self) -> Double {
        from.timeIntervalSinceReferenceDate.distance(to: to.timeIntervalSinceReferenceDate)
    }
}

internal extension String {
    /// Validate that the String chunk is processable by Leaf - can be used on chunks.
    ///
    /// If return value is .success, holds true if the file is possibly Leaf parseable (has valid tags) or false if
    /// no tag marks of any kind exist in the string.
    ///
    /// Failure return implies the file *IS* Leaf parseable but definitely has invalid tag entities. If the string
    /// value is non-empty, the string ends in an open tag identifier.
    func isLeafProcessable(_ entities: LeafEntities) -> Result<Bool, String> {
        if isEmpty { return .success(false) }
        
        var i = startIndex
        var lastTagMark: String.Index? = nil
        var last: String.Index { index(before: i) }
        var peek: String.Element { self[i] }
        
        func advance() { i = index(after: i) }
        var chunk: String { String(self[lastTagMark!...indices.last!]) }
        
        while i != endIndex {
            defer { if i != endIndex { advance() } }
            if peek != .tagIndicator { continue }
            if i != indices.first, self[last] == .backSlash { continue }
            lastTagMark = i
            if i == indices.last { return .failure(chunk) }
            advance()
            if peek == .leftParenthesis { return .success(true) }
            var possibleID = ""
            while i != endIndex, peek.isValidInIdentifier { possibleID.append(peek); advance() }
            if i == endIndex { return .failure(chunk) }
            if peek == .leftParenthesis {
                if !entities.openers.contains(possibleID) { return .failure("") } }
            else { if !entities.closers.contains(possibleID) { return .failure("") } }
        }
        return .success(lastTagMark != nil)
    }
}
