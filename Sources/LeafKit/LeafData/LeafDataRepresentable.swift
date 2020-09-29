import Foundation

// MARK: - LeafDataRepresentable Public Definition

/// Capable of being encoded as `LeafData`.
///
/// As `LeafData` has no direct initializers, adherants must implement `leafData` by using a public
/// static factory method from `LeafData`  to produce itself.
///
/// - WARNING: If adherant is a reference-type object, *BE AWARE OF THREADSAFETY*
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
    /// `Date` conversion is reliant on the configured `LeafTimestamp.referenceBase`
    public var leafData: LeafData {
        .double(timeIntervalSince(Date(timeIntervalSinceReferenceDate: LeafTimestamp.referenceBase.interval))) }
}

extension Array where Element == LeafData {
    public var leafData: LeafData { .array(map {$0}) }
}

extension Dictionary where Key == String, Value == LeafData {
    public var leafData: LeafData { .dictionary(mapValues {$0}) }
}

extension Set: LeafDataRepresentable where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Array: LeafDataRepresentable where Element: LeafDataRepresentable {
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Dictionary: LeafDataRepresentable where Key == String, Value: LeafDataRepresentable {
    public var leafData: LeafData { .dictionary(mapValues {$0.leafData}) }
}
