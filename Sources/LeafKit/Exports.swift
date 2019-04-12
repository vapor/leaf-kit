@_exported import NIO

extension Character {
    public static var tagIndicator: Character = .octothorpe
    
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
    static let Z = "Z".first!
    static let a = "a".first!
    static let z = "z".first!
    
    static let zero = "0".first!
    static let nine = "9".first!
    
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
    
    var isUppercaseLetter: Bool {
        return (.A ... .Z).contains(self)
    }
    
    var isLowercaseLetter: Bool {
        return (.a ... .z).contains(self)
    }
    
    var isAllowedInVariable: Bool {
        return self.isLowercaseLetter || self.isUppercaseLetter
    }
}
