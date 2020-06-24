// MARK: Subject to change prior to 1.0.0 release

// MARK: - `Parameter` Token Type

// FIXME: Can't be internal because of `Syntax`
/// - Does `stringLiteral` need to exist - should `Constant` have a `String` case or should
///   `Constant` be renamed `Numeric` for clarity?

/// An associated value enum holding data, objects or values usable as parameters to a `.tag`
public enum Parameter: Equatable, CustomStringConvertible {
    case stringLiteral(String)
    case constant(Constant)
    case variable(name: String)
    case keyword(Keyword)
    case `operator`(Operator)
    case tag(name: String)
    
    /// Returns `parameterCase(parameterValue)`
    public var description: String {
        return name + "(" + short + ")"
    }
    
    /// Returns `parameterCase`
    var name: String {
        switch self {
            case .stringLiteral: return "stringLiteral"
            case .constant:      return "constant"
            case .variable:      return "variable"
            case .keyword:       return "keyword"
            case .operator:      return "operator"
            case .tag:           return "tag"
        }
    }
    
    /// Returns `parameterValue` or `"parameterValue"` as appropriate for type
    var short: String {
        switch self {
            case .stringLiteral(let s): return "\"\(s)\""
            case .constant(let c):      return "\(c)"
            case .variable(let v):      return "\(v)"
            case .keyword(let k):       return "\(k)"
            case .operator(let o):      return "\(o)"
            case .tag(let t):           return "\"\(t)\""
        }
    }
}

// MARK: - `Parameter`-Storable Types

/// `Keyword`s are identifiers which take precedence over syntax/variable names - may potentially have
/// representable state themselves as value when used with operators (eg, `true`, `false` when
/// used with logical operators, `nil` when used with equality operators, and so forth)
public enum Keyword: String, Equatable {
    case `in`, `true`, `false`, `self`, `nil`, `yes`, `no`
}

/// Mathematical and Logical operators
public enum Operator: String, Equatable, CustomStringConvertible {
    case not = "!"
    case equals = "=="
    case notEquals = "!="
    case greaterThan = ">"
    case greaterThanOrEquals = ">="
    case lessThan = "<"
    case lessThanOrEquals = "<="

    case plus = "+"
    case minus = "-"
    case divide = "/"
    case multiply = "*"

    case and = "&&"
    case or = "||"
    
    /// Raw string value of the operator - eg `!=`
    public var description: String { return rawValue }
}

/// An integer or double constant value parameter (eg `1_000`, `-42.0`)
///
/// #TODO
/// - This is somewhat confusingly named. Possibly would be better to rename as `Numeric`, since
///   `stringLiteral` *IS* a constant type, or else `stringLiteral` should be moved into this.
public enum Constant: CustomStringConvertible, Equatable {
    case int(Int)
    case double(Double)

    public var description: String {
        switch self {
            case .int(let i):    return i.description
            case .double(let d): return d.description
        }
    }
}

// MARK: - Internal Helper Extensions

internal extension Keyword {
    /// Whether a `Keyword`  can be interpreted as a Boolean values
    var isBooleanValued: Bool {
        switch self {
            case .true,
                 .false,
                 .yes,
                 .no: return true
            default:  return false
        }
    }
    
    /// For `Keyword`s which can be interpreted as Boolean values, return that value or nil
    var booleanValue: Bool? {
        switch self {
            case .true, .yes: return true
            case .false, .no: return false
            default:          return nil
        }
    }
}

internal extension Operator {
    /// Whether an operator is a logical operator (ie, takes `Bool` values)
    var isBoolean: Bool {
        switch self {
            case .not,
                 .equals,
                 .notEquals,
                 .greaterThan,
                 .greaterThanOrEquals,
                 .lessThan,
                 .lessThanOrEquals,
                 .and,
                 .or   : return true
            default    : return false
        }
    }
    
    /// Whether an operator is a binary operator (ie, takes both LHS and RHS arguments)
    var isBinary: Bool { self == .not ? false : true }
    
    /// Whether an operator is a unary prefix operator (ie, takes only a RHS argument)
    var isUnaryPrefix: Bool { self == .not ? true : false }
}
