// MARK: Stable?!

/// Mathematical and Logical operators
public enum LeafOperator: String, Hashable, CaseIterable, LKPrintable {
    // MARK: - Cases

    // Operator types:              Logic      Exist.       UnPre        Scope
    //                                |   Math    |   Infix   |   UnPost   |
    //   Logical Tests          --------------------------------------------
    case not             = "!"  //    X                       X
    case equal           = "==" //    X                 X
    case unequal         = "!=" //    X                 X
    case greater         = ">"  //    X                 X
    case greaterOrEqual  = ">=" //    X                 X
    case lesser          = "<"  //    X                 X
    case lesserOrEqual   = "<=" //    X                 X
    case and             = "&&" //    X                 X
    case or              = "||" //    X                 X
    case xor             = "^^" //    X                 X
    //   Mathematical Calcs     // -----------------------------------------
    case plus            = "+"  //          X           X
    case minus           = "-"  //          X     X     X     X
    case divide          = "/"  //          X           X
    case multiply        = "*"  //          X           X
    case modulo          = "%"  //          X           X
    //   Assignment             // -----------------------------------------
    case assignment      = "="  //                X     X
    case compoundPlus    = "+=" //
    case compoundMinus   = "-=" //
    case compoundDiv     = "/=" //
    case compoundMult    = "*=" //
    case compoundMod     = "%=" //
    //   Existential            // -----------------------------------------
    case evaluate        = "`"  //                X           X
    //   Scoping                // -----------------------------------------
    case scopeRoot       = "$"  //                            X           X
    case scopeMember     = "."  //                      X                 X
    case subOpen         = "["  //                      X                 X
    case subClose        = "]"  //                                  X     X
    case subScript       = "[]" //   --- Not parseable - only internal
    //   Conditional            // -----------------------------------------
    case nilCoalesce     = "??" //                X     X
    case ternaryTrue     = "?"  //                X     X
    case ternaryFalse    = ":"  //                X     X

    /// Raw string value of the operator - eg `&&`
    public var short: String { rawValue }

    /// Long form description - eg `Logical And: &&`
    public var description: String {
        let str: String
        switch self {
            case .and            : str = "Logical And"
            case .assignment     : str = "Assignment"
            case .compoundPlus   : str = "Compound Plus"
            case .compoundMinus  : str = "Compound Minus"
            case .compoundDiv    : str = "Compound Division"
            case .compoundMult   : str = "Compound Multiplication"
            case .compoundMod    : str = "Compound Modulo"
            case .divide         : str = "Division"
            case .equal          : str = "Equality"
            case .evaluate       : str = "Evaluation"
            case .greater        : str = "Greater"
            case .greaterOrEqual : str = "Greater or Equal"
            case .lesser         : str = "Lesser"
            case .lesserOrEqual  : str = "Lesser or Equal"
            case .minus          : str = "Minus"
            case .modulo         : str = "Modulo"
            case .multiply       : str = "Multiplication"
            case .nilCoalesce    : str = "Nil Coalesce"
            case .not            : str = "Logical Not"
            case .or             : str = "Logical Or"
            case .plus           : str = "Plus"
            case .scopeMember    : str = "Scoping Accessor"
            case .scopeRoot      : str = "Scoping Root"
            case .subClose       : str = "Subscript Open"
            case .subOpen        : str = "Subscript Close"
            case .subScript      : str = "Subscript"
            case .unequal        : str = "Unequality"
            case .xor            : str = "Logical XOr"
            case .ternaryTrue    : str = "Ternary True"
            case .ternaryFalse   : str = "Ternary False"
        }
        return "\(str): \(rawValue)"
    }
}

// MARK: - Internal Only
internal extension LeafOperator {
    /// Associated enum used with a `LeafOperator` to disambiguate contextual meaning
    enum Form: UInt8, Hashable, LKPrintable {
        case unaryPrefix
        case unaryPostfix
        case infix

        var description: String { short }
        var short: String       {
            switch self {
                case .unaryPrefix  : return "unaryPrefix"
                case .unaryPostfix : return "unaryPostfix"
                case .infix        : return "infix"
            }
        }
    }

    // MARK: - State booleans
    var logical: Bool { Self.logical.contains(self) }
    var mathematical: Bool { Self.mathematical.contains(self) }
    var assigning: Bool { Self.assigning.contains(self) }
    var scoping: Bool { Self.scoping.contains(self) }

    var unaryPrefix: Bool { Self.unaryPrefix.contains(self) }
    var unaryPostfix: Bool { Self.unaryPostfix.contains(self) }
    var infix: Bool { Self.infix.contains(self) }

    var lexable: Bool { !Self.unlexable.contains(self) }
    var parseable: Bool { !Self.unparseable.contains(self) }

    static var validCharacters: Set<Character> {
        Set<LeafOperator>(LeafOperator.allCases)
                    .subtracting(Self.unlexable)
                    .map { $0.rawValue }.joined()
                    .reduce(into: .init(), { $0.insert($1) })
    }

    /// For calculation operators only - scoping, assignment, ternary not applicable
    static let evalPrecedenceMap: [(check: ((LeafOperator) -> Bool), infixed: Bool)] = [
        // ??
        (check: { $0 == .nilCoalesce }, infixed: true),
        // ! (excluding prefix -)
        (check: { $0 == .not }, infixed: false),
        // *, /, %
        (check: { [.multiply, .divide, .modulo].contains($0) }, infixed: true),
        // +, -
        (check: { [.plus, .minus].contains($0) }, infixed: true),
        // >, >=, <, <=
        (check: { [.greater, .greaterOrEqual, .lesser, .lesserOrEqual].contains($0) }, infixed: true),
        // ==, !=
        (check: { $0 == .equal || $0 == .unequal }, infixed: true),
        // &&, ||, ^^
        (check: { $0 == .and || $0 == .or || $0 == .xor}, infixed: true),
    ]

}

// MARK: - Private Helpers
private extension LeafOperator {
    /// Set groupings for mapping if a particular operator belongs to a set
    enum States: UInt8, Hashable {
        case logical
        case mathematical
        case assigning
        case scoping
        case unaryPrefix
        case unaryPostfix
        case infix
        case unlexable
        case unparseable
    }

    static var logical      : Set<LeafOperator> { states[.logical]! }
    static var mathematical : Set<LeafOperator> { states[.mathematical]! }
    static var assigning    : Set<LeafOperator> { states[.assigning]! }
    static var scoping      : Set<LeafOperator> { states[.scoping]! }
    static var unaryPrefix  : Set<LeafOperator> { states[.unaryPrefix]! }
    static var unaryPostfix : Set<LeafOperator> { states[.unaryPostfix]! }
    static var infix        : Set<LeafOperator> { states[.infix]! }
    static var unlexable    : Set<LeafOperator> { states[.unlexable]! }
    static var unparseable  : Set<LeafOperator> { states[.unparseable]! }

    static let states: [States: Set<LeafOperator>] = [
        .logical     : [not, equal, unequal, greater, greaterOrEqual,
                        lesser, lesserOrEqual, and, or],
        .mathematical: [plus, minus, divide, multiply, modulo],
        .assigning   : [assignment, compoundPlus, compoundMinus, compoundDiv,
                        compoundMult, compoundMod],
        .scoping     : [scopeRoot, scopeMember, subOpen, subClose],
        .unaryPrefix : [not, minus, evaluate, scopeRoot],
        .unaryPostfix: [subClose],
        .infix       : [equal, unequal, greater, greaterOrEqual, lesser,
                        lesserOrEqual, and, or, plus, minus, divide,
                        multiply, modulo, assignment, nilCoalesce,
                        scopeMember, subOpen, subScript,
                        ternaryTrue, ternaryFalse],
        .unlexable   : [evaluate, subScript],
        .unparseable : [evaluate]
    ]
}
