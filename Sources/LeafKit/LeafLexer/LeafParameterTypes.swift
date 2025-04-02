// MARK: - `Parameter` Token Type

/// An associated value enum holding data, objects or values usable as parameters to a `.tag`
public enum Parameter: Equatable, CustomStringConvertible, Sendable {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(LeafKeyword)
    case `operator`(LeafOperator)
    case tag(name: String)

    /// Returns `parameterCase(parameterValue)`
    public var description: String {
        "\(self.name)(\(self.short))"
    }

    /// Returns `parameterCase`
    var name: String {
        switch self {
        case .stringLiteral: "stringLiteral"
        case .constant: "constant"
        case .variable: "variable"
        case .keyword: "keyword"
        case .operator: "operator"
        case .tag: "tag"
        }
    }

    /// Returns `parameterValue` or `"parameterValue"` as appropriate for type
    var short: String {
        switch self {
        case .stringLiteral(let s): "\"\(s)\""
        case .constant(let c): "\(c)"
        case .variable(let v): "\(v)"
        case .keyword(let k): "\(k)"
        case .operator(let o): "\(o)"
        case .tag(let t): "\"\(t)\""
        }
    }
}

// MARK: - `Parameter`-Storable Types

/// `Keyword`s are identifiers which take precedence over syntax/variable names - may potentially have
/// representable state themselves as value when used with operators (eg, `true`, `false` when
/// used with logical operators, `nil` when used with equality operators, and so forth)
public enum LeafKeyword: String, Equatable, Sendable {
    // MARK: Public - Cases

    //                      Eval -> Bool / Other
    //                   -----------------------
    case `in`,  //
        `true`,  //   X       T
        `false`
    case
        this = "self"
    case
        `nil`,  //   X       F     X
        `yes`,  //   X       T
        `no`  //   X       F

    // MARK: Internal Only

    // State booleans
    var isEvaluable: Bool {
        self != .in
    }

    var isBooleanValued: Bool {
        [.true, .false, .nil, .yes, .no].contains(self)
    }

    // Value or value-indicating returns
    var `nil`: Bool {
        self == .nil
    }

    var identity: Bool {
        self == .this
    }

    var bool: Bool? {
        guard self.isBooleanValued else {
            return nil
        }
        return [.true, .yes].contains(self)
    }
}

// MARK: - Operator Symbols

// swift-format-ignore
/// Mathematical and Logical operators
public enum LeafOperator: String, Equatable, CustomStringConvertible, CaseIterable, Sendable {
    // MARK: Public - Cases

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

    /// Raw string value of the operator - eg `!=`
    public var description: String {
        self.rawValue
    }

    // MARK: Internal Only

    // State booleans
    var logical: Bool {
        Self.states["logical"]!.contains(self)
    }

    var mathematical: Bool {
        Self.states["mathematical"]!.contains(self)
    }

    var existential: Bool {
        Self.states["existential"]!.contains(self)
    }

    var scoping: Bool {
        Self.states["scoping"]!.contains(self)
    }

    var unaryPrefix: Bool {
        Self.states["unaryPrefix"]!.contains(self)
    }

    var unaryPostfix: Bool {
        Self.states["unaryPostfix"]!.contains(self)
    }

    var infix: Bool {
        Self.states["unaryPostfix"]!.contains(self)
    }

    var available: Bool {
        !Self.states["unavailable"]!.contains(self)
    }

    static let precedenceMap: [(check: (@Sendable (LeafOperator) -> Bool), infixed: Bool)] = [
        (check: { $0 == .not }, infixed: false), // unaryNot
        (check: { $0 == .multiply || $0 == .divide || $0 == .modulo }, infixed: true), // Mult/Div/Mod
        (check: { $0 == .plus || $0 == .minus }, infixed: true), // Plus/Minus
        (check: { $0 == .greater || $0 == .greaterOrEqual }, infixed: true), // >, >=
        (check: { $0 == .lesser || $0 == .lesserOrEqual }, infixed: true), // <, <=
        (check: { $0 == .equal || $0 == .unequal }, infixed: true), // !, !=
        (check: { $0 == .and || $0 == .or }, infixed: true), // &&, ||
    ]

    // MARK: Private Only

    private static let states: [String: Set<LeafOperator>] = [
        "logical"       : [.not, .equal, .unequal, .greater, .greaterOrEqual,
                           .lesser, .lesserOrEqual, .and, .or],
        "mathematical"  : [.plus, .minus, .divide, .multiply, modulo],
        "existential"   : [.assignment, .nilCoalesce, .minus, .evaluate],
        "scoping"       : [.scopeRoot, .scopeMember, .subOpen, .subClose],
        "unaryPrefix"   : [.not, .minus, .evaluate, .scopeRoot],
        "unaryPostfix"  : [.subClose],
        "infix"         : [.equal, .unequal, .greater, .greaterOrEqual, .lesser,
                           .lesserOrEqual, .and, .or, .plus, .minus, .divide,
                           .multiply, .modulo, .assignment, .nilCoalesce,
                           .scopeMember, .subOpen],
        "unavailable"   : [.assignment, .nilCoalesce, .evaluate, .scopeRoot,
                           .scopeMember, .subOpen, .subClose]
    ]
}

/// An integer or double constant value parameter (eg `1_000`, `-42.0`)
public enum Constant: CustomStringConvertible, Equatable, Sendable {
    case int(Int)
    case double(Double)

    public var description: String {
        switch self {
        case .int(let i): i.description
        case .double(let d): d.description
        }
    }
}
