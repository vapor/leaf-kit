// swift-format-ignore
/// Various helper identities for convenience
extension Character {

    // MARK: - LeafToken helpers

    var isValidInTagName: Bool {
        self.isLowercaseLetter || self.isUppercaseLetter
    }

    var isValidInParameter: Bool {
        self.isValidInTagName ||
        self.isValidOperator ||
        self.isValidInNumeric
    }

    var canStartNumeric: Bool {
        (.zero ... .nine) ~= self
    }

    var isValidInNumeric: Bool {
        self.canStartNumeric ||
        self == .underscore ||
        self == .binaryNotation ||
        self == .octalNotation ||
        self == .hexNotation ||
        self.isHexadecimal ||
        self == .period
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
             .vertical:
            true
        default:
            false
        }
    }

    // MARK: - General group-membership identities (Internal)

    var isHexadecimal: Bool {
        (.zero ... .nine).contains(self) ||
        (.A ... .F).contains(self) ||
        (.a ... .f).contains(self) ||
        self == .hexNotation
    }

    var isOctal: Bool {
        (.zero ... .seven).contains(self) || self == .octalNotation
    }

    var isBinary: Bool {
        self == .zero || self == .one || self == .binaryNotation
    }

    var isUppercaseLetter: Bool {
        (.A ... .Z).contains(self)
    }

    var isLowercaseLetter: Bool {
        (.a ... .z).contains(self)
    }

    // MARK: - General helpers

    static let newLine: Self = "\n"
    static let quote: Self = "\""
    static let octothorpe: Self = "#"
    static let leftParenthesis: Self = "("
    static let backSlash: Self = "\\"
    static let rightParenthesis: Self = ")"
    static let comma: Self = ","
    static let space: Self = " "
    static let colon: Self = ":"
    static let period: Self = "."
    static let A: Self = "A"
    static let F: Self = "F"
    static let Z: Self = "Z"
    static let a: Self = "a"
    static let f: Self = "f"
    static let z: Self = "z"

    static let zero: Self = "0"
    static let one: Self = "1"
    static let seven: Self = "7"
    static let nine: Self = "9"
    static let binaryNotation: Self = "b"
    static let octalNotation: Self = "o"
    static let hexNotation: Self = "x"

    static let plus: Self = "+"
    static let minus: Self = "-"
    static let star: Self = "*"
    static let forwardSlash: Self = "/"
    static let percent: Self = "%"
    static let equals: Self = "="
    static let exclamation: Self = "!"
    static let lessThan: Self = "<"
    static let greaterThan: Self = ">"
    static let ampersand: Self = "&"
    static let vertical: Self = "|"
    static let underscore: Self = "_"
}
