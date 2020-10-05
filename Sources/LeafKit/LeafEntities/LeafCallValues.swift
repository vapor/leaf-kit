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
    let values: [LeafData]
    let labels: [String: Int]
}

public extension LeafCallValues {
    /// Get the value at the specified 0-based index.
    ///
    /// Out of bounds positions return `.trueNil`
    subscript(index: Int) -> LeafData { (0..<count).contains(index) ? values[index] : .trueNil }
    
    /// Get the value associated with the registered label in function's `callSignature`
    ///
    /// Out of bounds positions return `.trueNil`
    subscript(index: String) -> LeafData { labels[index] != nil ? self[labels[index]!] : .trueNil }
    
    var count: Int { values.count }
}

internal extension LeafCallValues {
    /// Generate fulfilled LeafData call values from symbols in incoming tuple
    init?(_ sig:[LeafCallParameter],
          _ tuple: LKTuple?,
          _ symbols: inout LKVarStack) {
        if tuple == nil && !sig.isEmpty { return nil }
        guard let tuple = tuple else { values = []; labels = [:]; return }
        self.labels = tuple.labels
        self.values = tuple.values.enumerated().compactMap {
            sig[$0.offset].match($0.element.evaluate(&symbols)) }
        /// Some values not matched - call fails
        if count < tuple.count { return nil }
    }

    init(_ values: [LeafData], _ labels: [String: Int]) {
        self.values = values
        self.labels = labels
    }
}
