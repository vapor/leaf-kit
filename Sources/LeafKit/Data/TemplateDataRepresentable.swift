import Foundation

/// Capable of being encoded as `LeafData`.
public protocol LeafDataRepresentable {
    /// Converts `self` to `LeafData` or throws an error if `self`
    /// cannot be converted.
    func convertToLeafData() throws -> LeafData
}

// MARK: Default Conformances

extension String: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .string(self)
    }
}

extension FixedWidthInteger {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        guard self > Int.min && self < Int.max else {
            throw "todo" //TemplateKitError(identifier: "intSize", reason: "\(Self.self) \(self) cannot be represented by an Int.")
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

extension Optional {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        guard let wrapped = self else { return .null }
        fatalError()
//        if let wrapped = self.wrapped {
//            if let data = wrapped as? LeafDataRepresentable {
//                return try data.convertToLeafData()
//            } else {
//                throw TemplateKitError(
//                    identifier: "convertOptional",
//                    reason: "Optional type `\(Self.self)` is not `LeafDataRepresentable`"
//                )
//            }
//        } else {
//            return .null
//        }
    }
}

extension Optional: LeafDataRepresentable { }

extension Bool: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .bool(self)
    }
}

extension Double: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .double(self)
    }
}

extension Float: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .double(Double(self))
    }
}

extension UUID: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .string(description)
    }
}

extension Date: LeafDataRepresentable {
    /// See `LeafDataRepresentable`
    public func convertToLeafData() throws -> LeafData {
        return .double(timeIntervalSince1970)
    }
}
