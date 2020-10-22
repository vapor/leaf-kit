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

/// `LeafDataRepresentable` with a specified, fixed data type that is *always* returned (whether optional or not)
public protocol LeafDataFixedRepresentation: LeafDataRepresentable {
    static var celf: LeafDataType { get }
}

// MARK: - Default Conformances

extension String: LeafDataFixedRepresentation {
    public static var celf: LeafDataType { .string }
    public var leafData: LeafData { .string(self) }
}

extension FixedWidthInteger {
    public static var celf: LeafDataType { .int }
    public var leafData: LeafData { .int(Int(exactly: self)) }
}

extension Int8: LeafDataFixedRepresentation {}
extension Int16: LeafDataFixedRepresentation {}
extension Int32: LeafDataFixedRepresentation {}
extension Int64: LeafDataFixedRepresentation {}
extension Int: LeafDataFixedRepresentation {}
extension UInt8: LeafDataFixedRepresentation {}
extension UInt16: LeafDataFixedRepresentation {}
extension UInt32: LeafDataFixedRepresentation {}
extension UInt64: LeafDataFixedRepresentation {}
extension UInt: LeafDataFixedRepresentation {}

extension BinaryFloatingPoint {
    public static var celf: LeafDataType { .double }
    public var leafData: LeafData { .double(Double(exactly: self)) }
}

extension Float: LeafDataFixedRepresentation {}
extension Double: LeafDataFixedRepresentation {}
#if arch(i386) || arch(x86_64)
extension Float80: LeafDataFixedRepresentation {}
#endif

extension Bool: LeafDataFixedRepresentation {
    public static var celf: LeafDataType { .bool }
    public var leafData: LeafData { .bool(self) }
}

extension UUID: LeafDataFixedRepresentation {
    public static var celf: LeafDataType { .string }
    public var leafData: LeafData { .string(description) }
}

extension Date: LeafDataFixedRepresentation {
    public static var celf: LeafDataType { .double }
    /// `Date` conversion is reliant on the configured `LeafTimestamp.referenceBase`
    public var leafData: LeafData {
        .double(timeIntervalSince(Date(timeIntervalSinceReferenceDate: LeafTimestamp.referenceBase.interval))) }
}

extension Set: LeafDataRepresentable, LeafDataFixedRepresentation
                                    where Element: LeafDataRepresentable {
    public static var celf: LeafDataType { .array }
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Array: LeafDataRepresentable, LeafDataFixedRepresentation
                                    where Element: LeafDataRepresentable {
    public static var celf: LeafDataType { .array }
    public var leafData: LeafData { .array(map {$0.leafData}) }
}

extension Dictionary: LeafDataRepresentable, LeafDataFixedRepresentation
                       where Key == String, Value: LeafDataRepresentable {
    public static var celf: LeafDataType { .dictionary }
    public var leafData: LeafData { .dictionary(mapValues {$0.leafData}) }
}

extension Optional: LeafDataRepresentable, LeafDataFixedRepresentation
                       where Wrapped: LeafDataFixedRepresentation {
    public static var celf: LeafDataType { Wrapped.celf }
    public var leafData: LeafData { self?.leafData ?? .init(.optional(nil, Self.celf)) }
}
