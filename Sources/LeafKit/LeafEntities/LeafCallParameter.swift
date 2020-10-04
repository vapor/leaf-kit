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
    
    /// Shorthand convenience for an unlabled, non-optional, undefaulted parameter of a single type
    public static func type(_ type: LeafDataType) -> Self { .init(types: [type]) }
    /// Shorthand convenience for an unlabled, non-optional, undefaulted parameter of `[types]`
    public static func types(_ types: Set<LeafDataType>) -> Self { .init(types: types) }
    /// Shorthand convenience for an unlabled, undefaulted parameter of `[types]?`
    public static func optionalTypes(_ types: Set<LeafDataType>) -> Self { .init(types: types, optional: true) }
    
    /// Any `LeafDataType` but `.void`
    static var any: Self { .types(.any) }
    /// `LeafDataType` == `Collection`
    static var collections: Self { .types(.collections) }
    /// `LeafDataType` == `SignedNumeric`
    static var numerics: Self { .types(.numerics) }
    
    static var string: Self { .type(.string) }
    static var int: Self { .type(.int) }
    static var double: Self { .type(.double) }
    static var void: Self { .type(.void) }
    static var bool: Self { .type(.bool) }
    static var data: Self { .type(.data) }
    
    static func string(labeled: String?, optional: Bool = false, defaultValue: LeafData? = nil) -> Self {
        .init(label: labeled, types: .string, optional: optional, defaultValue: defaultValue) }
    static func double(labeled: String?, optional: Bool = false, defaultValue: LeafData? = nil) -> Self {
        .init(label: labeled, types: .double, optional: optional, defaultValue: defaultValue) }
    static func int(labeled: String?, optional: Bool = false, defaultValue: LeafData? = nil) -> Self {
        .init(label: labeled, types: .int, optional: optional, defaultValue: defaultValue) }
    static func bool(labeled: String?, optional: Bool = false, defaultValue: LeafData? = nil) -> Self {
        .init(label: labeled, types: .bool, optional: optional, defaultValue: defaultValue) }
    
    static var array: Self { .type(.array) }
    static var dictionary: Self { .type(.dictionary) }

    /// `(value(1), isValid: bool(true), ...)`
    public var description: String { short }
    var short: String {
        "\(label != nil ? "\(label!): " : "")\(types.description)\(optional ? "?" : "")\(defaultValue != nil ? " = \(defaultValue!.short)" : "")"
    }
}

internal extension LeafCallParameter {
    /// Verify the `CallParameter` is valid
    func _sanity() {
        precondition(!types.isEmpty,
                     "Parameter must specify at least one type")
        precondition(!types.contains(.void),
                     "Parameters cannot take .void types")
        precondition(!(label?.isEmpty ?? false) && label != "_",
                     "Use nil for unlabeled parameters, not empty strings or _")
        precondition(label?.isValidLeafIdentifier ?? true,
                     "Label must be a valid, non-keyword Leaf identifier")
        precondition(types.contains(defaultValue?.celf ?? types.first!),
                     "Default value is not a match for the argument types")
    }
    
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
}
