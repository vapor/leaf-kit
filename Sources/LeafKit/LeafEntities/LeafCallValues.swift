/// The concrete object a `LeafFunction` etc. will receive holding its call parameter values
///
/// Values for all parameters in function's call signature are guaranteed to be present and accessible via
/// subscripting using the 0-based index of the parameter position, or the label if one was specified. Data
/// is guaranteed to match at least one of the data types that was specified, and will only be optional if
/// the parameter specified that it accepts optionals at that position.
///
/// `.trueNil` is a unique case that never is an actual parameter value the function has received - it
/// signals out-of-bounds indexing of the parameter value object.
public struct LeafCallValues {
    /// Get the value associated with the registered label in function's `callSignature`
    subscript(index: String) -> LeafData { labels[index] != nil ? self[labels[index]!] : .trueNil }
    /// Get the value at the specified 0-based index
    subscript(index: Int) -> LeafData { (0..<count).contains(index) ? values[index] : .trueNil }

    internal let values: [LeafData]
    internal let labels: [String: Int]
    internal var count: Int { values.count }
    
    /// Generate fulfilled LeafData call values from symbols in incoming tuple
    internal init?(_ sig:[LeafCallParameter],
                   _ tuple: LKTuple?,
                   _ symbols: LKVarStack) {
        if tuple == nil && !sig.isEmpty { return nil }
        guard let tuple = tuple else { values = []; labels = [:]; return }
        self.labels = tuple.labels
        self.values = tuple.values.enumerated().compactMap {
            sig[$0.offset].match($0.element.evaluate(symbols)) }
        /// Some values not matched - call fails
        if count < tuple.count { return nil }
    }

    internal init(_ values: [LeafData], _ labels: [String: Int]) {
        self.values = values
        self.labels = labels
    }
}
