@_exported import NIO

extension UInt8 {
    static let newLine: UInt8 = 0xA
    static let quote: UInt8 = 0x22
    static let octothorpe: UInt8 = 0x23
    static let leftParenthesis: UInt8 = 0x28
    static let rightParenthesis: UInt8 = 0x29
    static let comma: UInt8 = 0x2C
    static let space: UInt8 = 0x20
    static let colon: UInt8 = 0x3A
    static let A: UInt8 = 0x41
    static let Z: UInt8 = 0x5A
    static let a: UInt8 = 0x61
    static let z: UInt8 = 0x7A
    
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
