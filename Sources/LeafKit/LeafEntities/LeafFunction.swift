// MARK: Subject to change prior to 1.0.0 release

/// An object that can take `LeafData` parameters and returns a single `LeafData` result
///
/// Example: `#date("now", "YYYY-mm-dd")`
public protocol LeafFunction {
    /// Array of the function's full call parameters
    static var callSignature: CallParameters { get }

    /// The concrete type(s) of `LeafData` the function returns
    static var returns: Set<LeafDataType> { get }

    /// Whether the function is invariant (has no potential side effects and always produces the same value given the same input)
    static var invariant: Bool { get }

    /// The actual evaluation function of the `LeafFunction`, which will be called with fully resolved data
    func evaluate(_ params: CallValues) -> LeafData
}

/// A `LeafFunction` that additionally can be used on a method on concrete `LeafData` types
///
/// Example: `#(aStringVariable.hasPrefix("prefix")`
/// The first parameter of the `.callSignature` provides the types the method can operate on. The method
/// will still be called using `LeafFunction.evaluate`, with the first parameter being the operand.
public protocol LeafMethod: LeafFunction {}

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
    subscript(index: String) -> LeafData { labels[index] != nil ? self[labels[index]!] : .trueNil }
    subscript(index: Int) -> LeafData { (0..<count).contains(index) ? values[index] : .trueNil }

    internal let values: [LeafData]
    internal let labels: [String: Int]
    internal var count: Int { values.count }

    internal init?(_ sig: CallParameters,
                   _ tuple: LKTuple?,
                   _ symbols: LKVarTablePointer) {
        guard let tuple = tuple else {
            if sig.isEmpty { values = []; labels = [:]; return }
            return nil
        }
        self.labels = tuple.labels
        do {
            self.values = try tuple.values.enumerated().map {
                let e = sig[$0.offset].match($0.element.evaluate(symbols))
                if let e = e { return e } else { throw "" }
            }
        } catch { return nil }
    }

    internal init(_ values: [LeafData], _ labels: [String: Int]) {
        self.values = values
        self.labels = labels
    }
}

/// A representation of a function parameter defintion - equivalent to a Swift parameter defintion
public struct LeafCallParameter: LKPrintable, Equatable {
    let label: String?
    let types: Set<LeafDataType>
    let optional: Bool
    let defaultValue: LeafData?

    /// Direct equivalency to a Swift parameter - see examples below
    ///
    /// For "func aFunction(`myLabel 0: String? = nil`)" (parameter will be available at `params["myLabel"]` or `params[0]`:
    ///    - `.init(label: "myLabel", types: [.string], optional: true, defaultValue: nil)`
    ///
    /// For "func aFunction(`_ 0: LeafData")` (parameter will be available at `params[0]`:
    ///    - `.init(types: Set(LeafDataType.allCases)) `
    public init(label: String? = nil,
                types: Set<LeafDataType>,
                optional: Bool = false,
                defaultValue: LeafData? = nil) {
        self.label = label
        self.types = types
        self.optional = optional
        self.defaultValue = defaultValue
        _sanity()
    }

    public static func types(_ types: Set<LeafDataType>) -> Self { .init(types: types) }
    public static func optionalTypes(_ types: Set<LeafDataType>) -> Self { .init(types: types, optional: true) }

    /// Return the parameter value if it's valid, coerce if possible, nil if not an interpretable match.
    func match(_ value: LeafData) -> LeafData? {
        /// 1:1 expected match, valid as long as expecatation isn't non-optional with optional value
        if types.contains(value.celf) { return !value.isNil || optional ? value : nil }
        /// If not 1:1 match, non-optional but expecting a bool, nil coerces implicitly to false
        if types.contains(.bool) && value.isNil, !optional { return .bool(false) }
        /// All remaining nil values are invalid
        if value.isNil { return nil }
        /// If only one type, return coerced value as long as it doesn't coerce to .trueNil (and for .bool always true)
        if types.count == 1 {
            let coerced = value.coerce(to: types.first!)
            return coerced != .trueNil ? coerced : types.first! == .bool ? .bool(true) : nil
        }
        /// Otherwise assume function will handle coercion itself as long as one potential match exists
        return types.first(where: {value.isCoercible(to: $0)}) != nil ? value : nil
    }

    /// `(_: value(1), isValid: bool(true), ...)`
    public var description: String { short }
    /// `(value(1), bool(true), ...)`
    var short: String {
        (label ?? "_") + ": " + types.description + (optional ? "?" : "") + (defaultValue != nil ? " = \(defaultValue!.short)" : "")
    }
}

