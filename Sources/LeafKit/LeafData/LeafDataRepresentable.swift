// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// Capable of being encoded as `LeafData`.
public protocol LeafDataRepresentable {
    /// Converts `self` to `LeafData`, returning `nil` if the conversion is not possible.
    var leafData: LeafData { get }
}

// MARK: Default Conformances

extension String: LeafDataRepresentable {
    public var leafData: LeafData { .string(self) }
}

extension FixedWidthInteger {
    public var leafData: LeafData {
        guard let valid = Int(exactly: self) else { return .int(nil) }
        return .int(Int(valid))
    }
}

extension Int8: LeafDataRepresentable {}
extension Int16: LeafDataRepresentable {}
extension Int32: LeafDataRepresentable {}
extension Int64: LeafDataRepresentable {}
extension Int: LeafDataRepresentable {}
extension UInt8: LeafDataRepresentable {}
extension UInt16: LeafDataRepresentable {}
extension UInt32: LeafDataRepresentable {}
extension UInt64: LeafDataRepresentable {}
extension UInt: LeafDataRepresentable {}

extension BinaryFloatingPoint {
    public var leafData: LeafData {
        guard let valid = Double(exactly: self) else { return .double(nil) }
        return .double(Double(valid))
    }
}

extension Float: LeafDataRepresentable {}
extension Double: LeafDataRepresentable {}
#if arch(i386) || arch(x86_64)
extension Float80: LeafDataRepresentable {}
#endif

extension Bool: LeafDataRepresentable {
    public var leafData: LeafData { .bool(self) }
}

extension UUID: LeafDataRepresentable {
    public var leafData: LeafData { .string(LeafConfiguration.stringFormatter(description)) }
}

extension Date: LeafDataRepresentable {
    public var leafData: LeafData { .double(timeIntervalSince1970) }
}

extension Array where Element == LeafData {
    public var leafData: LeafData { .array(self.map { $0 }) }
}

extension Dictionary where Key == String, Value == LeafData {
    public var leafData: LeafData { .dictionary(self.mapValues { $0 }) }
}

extension Set where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(self.map { $0.leafData }) }
}

extension Array where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(self.map { $0.leafData }) }
}

extension Dictionary where Key == String, Value: LeafDataRepresentable {
    public var leafData: LeafData { .dictionary(self.mapValues { $0.leafData }) }
}
