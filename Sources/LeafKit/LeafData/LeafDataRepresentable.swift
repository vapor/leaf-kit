// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// Capable of being encoded as `LeafData`.
public protocol LeafDataRepresentable {
    /// Converts `self` to `LeafData`, returning `nil` if the conversion is not possible.
    var leafData: LeafData? { get }
}

// MARK: Default Conformances

extension String: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .string(self)
    }
}

extension FixedWidthInteger {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        guard self > Int.min && self < Int.max else {
            return nil
        }
        return .int(Int(self))
    }
}

extension Int8: LeafDataRepresentable { }
extension Int16: LeafDataRepresentable { }
extension Int32: LeafDataRepresentable { }
extension Int64: LeafDataRepresentable { }
extension Int: LeafDataRepresentable { }
extension UInt8: LeafDataRepresentable { }
extension UInt16: LeafDataRepresentable { }
extension UInt32: LeafDataRepresentable { }
extension UInt64: LeafDataRepresentable { }
extension UInt: LeafDataRepresentable { }

extension Bool: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .bool(self)
    }
}

extension Double: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .double(self)
    }
}

extension Float: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .double(Double(self))
    }
}

extension UUID: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .string(description)
    }
}

extension Date: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public var leafData: LeafData? {
        return .double(timeIntervalSince1970)
    }
}
