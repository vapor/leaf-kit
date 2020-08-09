
infix operator >?=: AssignmentPrecedence
infix operator <?=: AssignmentPrecedence

extension Comparable {
    /// Conditional shorthand for lhs = max(lhs, rhs)
    internal static func >?=(lhs: inout Self, rhs: Self) {
        lhs = max(lhs, rhs)
    }
    /// Conditional shorthand for lhs = min(lhs, rhs)
    internal static func <?=(lhs: inout Self, rhs: Self) {
        lhs = min(lhs, rhs)
    }
}
