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
    
    /// If the adherent has a single, specified `LeafDataType` that is *always* returned, non-nil
    ///
    /// Default implementation provided
    static var leafDataType: LeafDataType? { get }
}

public extension LeafDataRepresentable {
    static var leafDataType: LeafDataType? { nil }
}

// MARK: - Default Conformances

extension String: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .string }
    public var leafData: LeafData { .string(self) }
}

extension FixedWidthInteger {
    public var leafData: LeafData { .int(Int(exactly: self)) }
}

extension Int8: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension Int16: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension Int32: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension Int64: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension Int: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension UInt8: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension UInt16: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension UInt32: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension UInt64: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }
extension UInt: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .int } }

extension BinaryFloatingPoint {
    public var leafData: LeafData { .double(Double(exactly: self)) }
}

extension Float: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .double } }
extension Double: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .double } }
#if arch(i386) || arch(x86_64)
extension Float80: LeafDataRepresentable { public static var leafDataType: LeafDataType? { .double } }
#endif

extension Bool: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .bool }
    public var leafData: LeafData { .bool(self) }
}

extension UUID: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .string }
    public var leafData: LeafData { .string(description) }
}

extension Date: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .double }
    /// `Date` conversion is reliant on the configured `LeafTimestamp.referenceBase`
    public var leafData: LeafData {
        .double(
            Date(timeIntervalSinceReferenceDate: LeafTimestamp.referenceBase.interval) +-> self
//            timeIntervalSince(Date(timeIntervalSinceReferenceDate: LeafTimestamp.referenceBase.interval))
        ) }
}

extension Set: LeafDataRepresentable where Element: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .array }
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Array: LeafDataRepresentable where Element: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .array }
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Dictionary: LeafDataRepresentable where Key == String, Value: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { .dictionary }
    public var leafData: LeafData { .dictionary(mapValues {$0.leafData}) }
}

extension Optional: LeafDataRepresentable where Wrapped: LeafDataRepresentable {
    public static var leafDataType: LeafDataType? { Wrapped.leafDataType }
    public var leafData: LeafData { self?.leafData ?? .init(.nil(Self.leafDataType ?? .void)) }
}
