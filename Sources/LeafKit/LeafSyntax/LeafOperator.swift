// MARK: Subject to change prior to 1.0.0 release

/// Mathematical and Logical operators
public enum LeafOperator: String, Hashable, CaseIterable, SymbolPrintable {
    /// Associated enum used with a `LeafOperator` to disambiguate contextual meaning
    internal enum Form: String, Hashable, SymbolPrintable {
        case unaryPrefix
        case unaryPostfix
        case infix
        
        var description: String { rawValue }
        var short: String       { rawValue }
    }
    
    // MARK: - Cases
    
    // Operator types:              Logic      Exist.       UnPre        Scope
    //                                |   Math    |   Infix   |   UnPost   |
    //   Logical Tests          --------------------------------------------
    case not = "!"              //    X                       X
    case equal = "=="           //    X                 X
    case unequal = "!="         //    X                 X
    case greater = ">"          //    X                 X
    case greaterOrEqual = ">="  //    X                 X
    case lesser = "<"           //    X                 X
    case lesserOrEqual = "<="   //    X                 X
    case and = "&&"             //    X                 X
    case or = "||"              //    X                 X
    case xor = "^^"             //    X                 X
    //   Mathematical Calcs     // -----------------------------------------
    case plus = "+"             //          X           X
    case minus = "-"            //          X     X     X     X
    case divide = "/"           //          X           X
    case multiply = "*"         //          X           X
    case modulo = "%"           //          X           X
    //   Assignment/Existential //
    case assignment = "="       //                X     X
    case nilCoalesce = "??"     //                X     X
    case evaluate = "`"         //                X           X
    //   Scoping
    case scopeRoot = "$"        //                            X           X
    case scopeMember = "."      //                      X                 X
    case subOpen = "["          //                      X                 X
    case subClose = "]"         //                                  X     X
    case subScript = "[]"       //   --- Not parseable - only internal
    
    /// Raw string value of the operator - eg `!=`
    public var short: String       { rawValue }
    /// Long form description
    public var description: String {
        let str: String
        switch self {
            case .and            : str = "Logical And"
            case .assignment     : str = "Assignment"
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
        }
        return "\(str): \(rawValue)"
    }
    
    // MARK: Internal Only
    
    // State booleans
    internal var logical: Bool { Self.logical.contains(self) }
    internal var mathematical: Bool { Self.mathematical.contains(self) }
    internal var existential: Bool { Self.existential.contains(self) }
    internal var scoping: Bool { Self.scoping.contains(self) }
    
    internal var unaryPrefix: Bool { Self.unaryPrefix.contains(self) }
    internal var unaryPostfix: Bool { Self.unaryPostfix.contains(self) }
    internal var infix: Bool { Self.infix.contains(self) }
    
    internal var lexable: Bool { !Self.unlexable.contains(self) }
    internal var parseable: Bool { !Self.unparseable.contains(self) }
    
    internal static var validCharacters: Set<Character> {
        Set<LeafOperator>(LeafOperator.allCases)
                    .subtracting(Self.unlexable)
                    .map { $0.rawValue }.joined()
                    .reduce(into: .init(), { $0.insert($1) })
    }
    
    /// For calculation operators only - scoping & assignment not applicable
    internal static let evalPrecedenceMap: [(check: ((LeafOperator) -> Bool), infixed: Bool)] = [
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
    
    // MARK: Private Only
    
    /// Set groupings for mapping if a particular operator belongs to a set
    private enum States: Int, Hashable {
        case logical
        case mathematical
        case existential
        case scoping
        case unaryPrefix
        case unaryPostfix
        case infix
        case unlexable
        case unparseable
    }
    
    private static var logical: Set<LeafOperator> { Self.states[.logical]! }
    private static var mathematical: Set<LeafOperator> { Self.states[.mathematical]! }
    private static var existential: Set<LeafOperator> { Self.states[.existential]! }
    private static var scoping: Set<LeafOperator> { Self.states[.scoping]! }
    private static var unaryPrefix: Set<LeafOperator> { Self.states[.unaryPrefix]! }
    private static var unaryPostfix: Set<LeafOperator> { Self.states[.unaryPostfix]! }
    private static var infix: Set<LeafOperator> { Self.states[.infix]! }
    private static var unlexable: Set<LeafOperator> { Self.states[.unlexable]! }
    private static var unparseable: Set<LeafOperator> { Self.states[.unparseable]! }
    
    private static let states: [States: Set<LeafOperator>] = [
        .logical     : [not, equal, unequal, greater, greaterOrEqual,
                        lesser, lesserOrEqual, and, or],
        .mathematical: [plus, minus, divide, multiply, modulo],
        .existential : [assignment, nilCoalesce, minus, evaluate],
        .scoping     : [scopeRoot, scopeMember, subOpen, subClose],
        .unaryPrefix : [not, minus, evaluate, scopeRoot],
        .unaryPostfix: [subClose],
        .infix       : [equal, unequal, greater, greaterOrEqual, lesser,
                        lesserOrEqual, and, or, plus, minus, divide,
                        multiply, modulo, assignment, nilCoalesce,
                        scopeMember, subOpen, subScript],
        .unlexable   : [assignment, evaluate, subScript],
        .unparseable : [assignment, evaluate, subOpen, subClose]
        
    ]
}
