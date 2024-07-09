import NIOConcurrencyHelpers
/// Various helper identities for convenience
extension Character {

    // MARK: - LeafToken specific identities (Internal)
    static let tagIndicator = NIOLockedValueBox(Character.octothorpe)

    var isValidInTagName: Bool {
        return self.isLowercaseLetter
            || self.isUppercaseLetter
    }
    
    var isValidInParameter: Bool {
        return self.isValidInTagName
            || self.isValidOperator
            || self.isValidInNumeric
    }

    var canStartNumeric: Bool {
        return (.zero ... .nine) ~= self
    }

    var isValidInNumeric: Bool {
        return self.canStartNumeric
            || self == .underscore
            || self == .binaryNotation
            || self == .octalNotation
            || self == .hexNotation
            || self.isHexadecimal
            || self == .period
    }

    var isValidOperator: Bool {
        switch self {
            case .plus,
                 .minus,
                 .star,
                 .forwardSlash,
                 .percent,
                 .equals,
                 .exclamation,
                 .lessThan,
                 .greaterThan,
                 .ampersand,
                 .vertical: return true
            default:        return false
        }
    }
    
    // MARK: - General group-membership identities (Internal)
    
    var isHexadecimal: Bool {
        return (.zero ... .nine).contains(self)
            || (.A ... .F).contains(self.uppercased().first!)
            || self == .hexNotation
    }

    var isOctal: Bool {
        return (.zero ... .seven).contains(self)
        || self == .octalNotation
    }

    var isBinary: Bool {
        return (.zero ... .one).contains(self)
        || self == .binaryNotation
    }

    var isUppercaseLetter: Bool {
        return (.A ... .Z).contains(self)
    }

    var isLowercaseLetter: Bool {
        return (.a ... .z).contains(self)
    }
    
    // MARK: - General static identities (Internal)
    
    static let newLine = "\n".first!
    static let quote = "\"".first!
    static let octothorpe = "#".first!
    static let leftParenthesis = "(".first!
    static let backSlash = "\\".first!
    static let rightParenthesis = ")".first!
    static let comma = ",".first!
    static let space = " ".first!
    static let colon = ":".first!
    static let period = ".".first!
    static let A = "A".first!
    static let F = "F".first!
    static let Z = "Z".first!
    static let a = "a".first!
    static let z = "z".first!

    static let zero = "0".first!
    static let one = "1".first!
    static let seven = "7".first!
    static let nine = "9".first!
    static let binaryNotation = "b".first!
    static let octalNotation = "o".first!
    static let hexNotation = "x".first!

    static let plus = "+".first!
    static let minus = "-".first!
    static let star = "*".first!
    static let forwardSlash = "/".first!
    static let percent = "%".first!
    static let equals = "=".first!
    static let exclamation = "!".first!
    static let lessThan = "<".first!
    static let greaterThan = ">".first!
    static let ampersand = "&".first!
    static let vertical = "|".first!
    static let underscore = "_".first!
}
