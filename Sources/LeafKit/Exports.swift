// MARK: Subject to change prior to 1.0.0 release
// MARK: -

@_exported import NIO

extension String: Error {}

// MARK: - Static Conveniences

public extension Set where Element == LeafDataType {
    /// Any `LeafDataType` but `.void`
    static var any: Self { Set(LeafDataType.allCases.filter {$0 != .void}) }
    /// `LeafDataType` == `Collection`
    static var collections: Self { [.array, .dictionary] }
    /// `LeafDataType` == `SignedNumeric`
    static var numerics: Self { [.int, .double] }
}


/// Public helper identities
public extension Character {
    /// Global setting of `tagIndicator` for Leaf-Kit - by default, `#`
    internal(set) static var tagIndicator: Character = .octothorpe
}

public extension String {
    var isValidIdentifier: Bool {
        !isEmpty && allSatisfy({$0.isValidInIdentifier})
            && first?.canStartIdentifier ?? false
    }
}


/// Various internal helper identities for convenience
internal extension Character {
    // MARK: - LeafToken specific identities
    
    var canStartIdentifier: Bool { isLowercaseLetter || isUppercaseLetter || self == .underscore }
    var isValidInIdentifier: Bool { self.canStartIdentifier || self.isDecimal }
    
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
    var isHexadecimal: Bool {
        guard !isDecimal else { return true }
        return (.A ... .F) ~= self.uppercased().first!
    }

    
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


internal extension Double {
    var formatSeconds: String {
        let abs = self.magnitude
        if abs * 10 > 1 { return String(format: "%.3f%", abs) + " s"}
        if abs * 1_000 > 1 { return String(format: "%.3f%", abs * 1_000) + " ms" }
        return String(format: "%.3f%", abs * 1_000_000) + " µs"
    }
}

internal extension Int {
    var formatBytes: String { UInt64(self.magnitude).formatBytes }
}

internal extension UInt64 {
    var formatBytes: String {
        if self > 1024 * 512 { return String(format: "%.2fmB", Double(self)/1024.0/1024.0) }
        if self > 512 { return String(format: "%.2fkB", Double(self)/1024.0) }
        return "\(self)B"
    }
}
