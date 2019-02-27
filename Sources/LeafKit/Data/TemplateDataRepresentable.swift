/// Capable of being encoded as `TemplateData`.
public protocol TemplateDataRepresentable {
    /// Converts `self` to `TemplateData` or throws an error if `self`
    /// cannot be converted.
    func convertToTemplateData() throws -> TemplateData
}

// MARK: Default Conformances

extension String: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .string(self)
    }
}

extension FixedWidthInteger {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        guard self > Int.min && self < Int.max else {
            throw TemplateKitError(identifier: "intSize", reason: "\(Self.self) \(self) cannot be represented by an Int.")
        }
        return .int(Int(self))
    }
}

extension Int8: TemplateDataRepresentable { }
extension Int16: TemplateDataRepresentable { }
extension Int32: TemplateDataRepresentable { }
extension Int64: TemplateDataRepresentable { }
extension Int: TemplateDataRepresentable { }
extension UInt8: TemplateDataRepresentable { }
extension UInt16: TemplateDataRepresentable { }
extension UInt32: TemplateDataRepresentable { }
extension UInt64: TemplateDataRepresentable { }
extension UInt: TemplateDataRepresentable { }

extension OptionalType {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        if let wrapped = self.wrapped {
            if let data = wrapped as? TemplateDataRepresentable {
                return try data.convertToTemplateData()
            } else {
                throw TemplateKitError(
                    identifier: "convertOptional",
                    reason: "Optional type `\(Self.self)` is not `TemplateDataRepresentable`"
                )
            }
        } else {
            return .null
        }
    }
}

extension Optional: TemplateDataRepresentable { }

extension Bool: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .bool(self)
    }
}

extension Double: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .double(self)
    }
}

extension Float: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .double(Double(self))
    }
}

extension UUID: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .string(description)
    }
}

extension Date: TemplateDataRepresentable {
    /// See `TemplateDataRepresentable`
    public func convertToTemplateData() throws -> TemplateData {
        return .double(timeIntervalSince1970)
    }
}
