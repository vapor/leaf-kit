@_exported import NIO

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
