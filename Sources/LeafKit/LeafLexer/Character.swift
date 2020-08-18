/// Various internal helper identities for convenience
internal extension Character {
    // MARK: - LKToken specific identities

    var canStartIdentifier: Bool { isLowercaseLetter || isUppercaseLetter || self == .underscore }
    var isValidInIdentifier: Bool { canStartIdentifier || isDecimal }

    var isValidInParameter: Bool { isValidInIdentifier || isValidOperator || isValidInNumeric }

    var isValidOperator: Bool { LeafOperator.validCharacters.contains(self) }

    var canStartNumeric: Bool { isDecimal }
    var isValidInNumeric: Bool {
        if isHexadecimal { return true }
        return [.binaryNotation, .octalNotation, .hexNotation,
                .underscore, .period].contains(self)
    }

    var isWhiteSpace: Bool { [.newLine, .space, .tab].contains(self) }

    // MARK: - General group-membership identities
    var isUppercaseLetter: Bool { (.A    ... .Z     ) ~= self }
    var isLowercaseLetter: Bool { (.a    ... .z     ) ~= self }

    var isBinary: Bool          { (.zero ... .one   ) ~= self }
    var isOctal: Bool           { (.zero ... .seven ) ~= self }
    var isDecimal: Bool         { (.zero ... .nine  ) ~= self }
    var isHexadecimal: Bool     { isDecimal ? true
                                            : (.A ... .F) ~= uppercased().first! }

    // MARK: - General static identities
    static let newLine = "\n".first!
    static let quote = "\"".first!
    static let octothorpe = "#".first!
    static let backSlash = "\\".first!
    static let leftParenthesis = "(".first!
    static let rightParenthesis = ")".first!
    static let leftBracket = "[".first!
    static let rightBracket = "]".first!
    static let comma = ",".first!
    static let space = " ".first!
    static let tab = "\t".first!
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
    static let equals = "=".first!
    static let exclamation = "!".first!
    static let lessThan = "<".first!
    static let greaterThan = ">".first!
    static let ampersand = "&".first!
    static let vertical = "|".first!
    static let underscore = "_".first!
    static let modulo = "%".first!
    static let upcaret = "^".first!
}
