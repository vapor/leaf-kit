// MARK: Subject to change prior to 1.0.0 release

import Foundation

// MARK: - LeafDataRepresentable Public Definition

/// Capable of being encoded as `LeafData`.
///
/// As `LeafData` has no direct initializers, adherants must implement `leafData` by using a public
/// static factory method to produce itself.
public protocol LeafDataRepresentable {
    /// Converts `self` to `LeafData`, returning `nil` if the conversion is not possible.
    var leafData: LeafData { get }
}

// MARK: - Default Conformances

extension String: LeafDataRepresentable {
    public var leafData: LeafData { .string(self) }
}

extension FixedWidthInteger {
    public var leafData: LeafData { Int(exactly: self).map { .int($0) } ?? .int(nil) }
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
    public var leafData: LeafData { Double(exactly: self).map { .double($0) } ?? .double(nil) }
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
    public var leafData: LeafData { .string(description) }
}

extension Date: LeafDataRepresentable {
    public var leafData: LeafData { .double(timeIntervalSince1970) }
}

extension Array where Element == LeafData {
    public var leafData: LeafData { .array(map { $0 }) }
}

extension Dictionary where Key == String, Value == LeafData {
    public var leafData: LeafData { .dictionary(mapValues { $0 }) }
}

extension Set where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(map { $0.leafData }) }
}

extension Array where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(map { $0.leafData }) }
}

extension Dictionary where Key == String, Value: LeafDataRepresentable {
    public var leafData: LeafData { .dictionary(mapValues { $0.leafData }) }
}
