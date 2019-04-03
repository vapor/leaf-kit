@_exported import NIO

extension Character {
    static let newLine = "\n".first!
    static let quote = "\"".first!
    static let octothorpe = "#".first!
    static let leftParenthesis = "(".first!
    static let backSlash = "\\".first!
    static let rightParenthesis = ")".first!
    static let comma = ",".first!
    static let space = " ".first!
    static let colon = ":".first!
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
    
//    var scalar: Unicode.Scalar {
//        return Unicode.Scalar(UInt8(self))
//    }
    
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

extension UInt8 {
    static let newLine: UInt8 = "\n".utf8.first!
    static let quote: UInt8 = "\"".utf8.first!
    static let octothorpe: UInt8 = "#".utf8.first!
    static let leftParenthesis: UInt8 = "(".utf8.first!
    static let backSlash: UInt8 = "\\".utf8.first!
    static let rightParenthesis: UInt8 = ")".utf8.first!
    static let comma: UInt8 = ",".utf8.first!
    static let space: UInt8 = " ".utf8.first!
    static let colon: UInt8 = ":".utf8.first!
    static let A: UInt8 = "A".utf8.first!
    static let Z: UInt8 = "Z".utf8.first!
    static let a: UInt8 = "a".utf8.first!
    static let z: UInt8 = "z".utf8.first!
    
    static let zero: UInt8 = "0".utf8.first!
    static let nine: UInt8 = "9".utf8.first!
    
    static let plus: UInt8 = "+".utf8.first!
    static let minus: UInt8 = "-".utf8.first!
    static let star: UInt8 = "*".utf8.first!
    static let forwardSlash: UInt8 = "/".utf8.first!
    static let equals: UInt8 = "=".utf8.first!
    static let exclamation: UInt8 = "!".utf8.first!
    static let lessThan: UInt8 = "<".utf8.first!
    static let greaterThan: UInt8 = ">".utf8.first!
    static let ampersand: UInt8 = "&".utf8.first!
    static let vertical: UInt8 = "|".utf8.first!
    
    var scalar: Unicode.Scalar {
        return Unicode.Scalar(self)
    }
    
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
