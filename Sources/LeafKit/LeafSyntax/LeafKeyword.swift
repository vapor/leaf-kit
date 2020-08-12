// MARK: Subject to change prior to 1.0.0 release

/// `Keyword`s are identifiers which take precedence over syntax/variable names - may potentially have
/// representable state themselves as value when used with operators (eg, `true`, `false` when
/// used with logical operators, `nil` when used with equality operators, and so forth)
public enum LeafKeyword: String, Hashable, CaseIterable, LKPrintable {
    // MARK: - Cases
    //               Eval -> Bool / Other
    //            -----------------------
    case `in`,    //
         `true`,  //   X       T
         `false`, //   X       F
         `self`,  //   X             X
         `nil`,   //   X       F     X
         `yes`,   //   X       T
         `no`,    //   X       F
         `_`,     //
         leaf     //
    
    // MARK: - LKPrintable
    public var description: String { rawValue }
    public var short: String { rawValue }

    // MARK: Internal Only
    /// Whether the keyword has an evaluable representation
    internal var isEvaluable: Bool { ![.in, ._, .leaf].contains(self) }
    /// Whether the keyword can represent a logical value
    internal var isBooleanValued: Bool { [.true, .false, .yes, .no].contains(self) }
    /// Evaluate to a logical state, if possible
    internal var bool: Bool? { isBooleanValued ? [.true, .yes].contains(self) : nil }
}
