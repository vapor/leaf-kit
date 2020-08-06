// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Protocols

/// A representation of a function parameter defintion - equivalent to a Swift parameter defintion
public struct CallParameter: SymbolPrintable, Equatable {
    internal let label: String?
    internal let types: Set<LeafDataType>
    internal let optional: Bool
    internal let defaultValue: LeafData?
    
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
    
    /// Return the parameter value if it's valid, coerce if possible, nil if not an interpretable match.
    internal func match(_ value: LeafData) -> LeafData? {
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
    
    static func types(_ types: Set<LeafDataType>) -> CallParameter { .init(types: types) }
    static func optionalTypes(_ types: Set<LeafDataType>) -> CallParameter { .init(types: types, optional: true) }
    
    /// `(_: value(1), isValid: bool(true), ...)`
    public var description: String { short }
    /// `(value(1), bool(true), ...)`
    var short: String {
        (label ?? "_") + ": " + types.description + (optional ? "?" : "") + (defaultValue != nil ? " = \(defaultValue!.short)" : "")
    }
}

/// A representation of a block's parsing parameters
public indirect enum ParseParameter: Hashable {
    /// A mapping of this position to a raw string `instantiate` will receive
    case unscopedVariable
    /// A mapping of a literal value
    case literal(String)
    /// A mapping of this position to the function signature parameters
    case callParameter
    /// A set of keywords the block accepts at this position
    case keyword(Set<LeafKeyword>)
    
    /// A tuple - `(x, y)`
    case tuple([ParseParameter])
    /// An expression - `(x in y)`
    case expression([ParseParameter])
}

/// The concrete object a `LeafFunction` will receive holding its parameter values
///
/// Values for all parameters in function's call signature are guaranteed to be present and accessible via
/// subscripting using the 0-based index of the parameter position, or the label if one was specified. Data
/// is guaranteed to match at least one of the data types that was specified, and will only be optional if
/// the parameter specified that it accepts optionals at that position. Special case handling
///
/// `.trueNil` is a unique case that never is an actual parameter value the function has received - it
/// signals out-of-bounds indexing of the parameter value object.
public struct ParameterValues {
    subscript(index: String) -> LeafData { self[labels[index] ?? -1] }
    subscript(index: Int) -> LeafData { values.indices.contains(index) ? values[index] : .trueNil }
    
    internal let values: [LeafData]
    internal let labels: [String: Int]
    
    internal init?(_ sig: [CallParameter],
                   _ tuple: LeafTuple,
                   _ symbols: SymbolMap) {
        if sig.isEmpty && tuple.isEmpty { values = []; labels = [:]; return }
        labels = tuple.labels
        do { values = try tuple.values.enumerated().map {
                let e = sig[$0.offset].match($0.element.evaluate(symbols))
                if let e = e { return e } else { throw "" } }
        } catch { return nil }
    }
    
    internal init(_ values: [LeafData], _ labels: [String: Int]) {
        self.values = values
        self.labels = labels
    }
}

/// `ScopeCount` dictates how many times a block will be evaluated
///
/// - `.discard` if immediately bypass the block's scope
/// - `.once` if only called once
/// - `.repeating(x)` if called a finite number of times
/// - `.indefinite` if number of calls is indeterminable
public typealias ScopeCount = Int?
public extension ScopeCount {
    static let discard: ScopeCount = 0
    static let once: ScopeCount = 1
    static let indefinite: ScopeCount = nil
    static func repeating(_ times: Int) -> ScopeCount  { times }
}

/// An object that can take `LeafData` parameters and returns a single `LeafData` result
///
/// Example: `#date("now", "YYYY-mm-dd")`
public protocol LeafFunction {
    /// Array of the function's full call parameters
    static var callSignature: [CallParameter] { get }
    
    /// The concrete type(s) of `LeafData` the function returns
    static var returns: Set<LeafDataType> { get }
    
    /// Whether the function is invariant (has no potential side effects and always produces the same value given the same input)
    static var invariant: Bool { get }
    
    /// The actual evaluation function of the `LeafFunction`, which will be called with fully resolved data
    func evaluate(_ params: ParameterValues) -> LeafData
}

/// A `LeafFunction` that additionally can be used on a method on concrete `LeafData` types
///
/// Example: `#(aStringVariable.hasPrefix("prefix")`
/// The first parameter of the `.signature` provides the types the method can operate on. The method
/// will still be called using `LeafFunction.evaluate` where the first parameter is the operand.
public protocol LeafMethod: LeafFunction {}

/// An object that can introduce variables and/or scope into a template for anything within the block
///
/// Example: `#for(value in dictionary)`
public protocol LeafBlock: LeafFunction {
    /// Provide any relevant parse signatures, if the block must be provided data at parse time.
    ///
    /// Ex: `#for` needs to provide a signature for `x in y` where x is a parse parameter that sets
    /// the variable name it will provide to its scope when evaluated, and y is a call parameter that it will
    /// receive when being evaluated.
    static var parseSignatures: [String: [ParseParameter]]? { get }
    
    /// Generate a concrete object of this type given concrete parameters at parse time
    /// - Parameters:
    ///   - parseParams: The parameters this object requires at parse time
    static func instantiate(_ signature: String?, _ params: [String]) throws -> Self
    
    /// If the object can be called with function syntax via `evaluate`
    static var evaluable: Bool { get }
    
    /// The variable names an instantiated `LeafBlock` will provide to its block, if any.
    ///
    /// These must be consistent throughout calls to the block. If the block type will *never* provide
    /// variables, return nil rather than an empty array.
    var scopeVariables: [String]? { get }
    
    /// The actual entry point function of a `LeafBlock`
    ///
    /// - Parameters:
    ///   - params: `ParameterValues` holding the Leaf data corresponding to the block's call signature
    ///   - variables: Dictionary of variable values the block is setting.
    /// - Returns:
    ///    - `ScopeValue` signals whether the block should be re-evaluated; 0 if discard,
    ///       >0 if a known amount, nil if unknown how many times it will need to be re-evaluated
    ///    - `.discard` or `once` are the predominant returns for most blocks
    ///    - `.indefinite` or `.repeating(x)` for looping blocks.
    ///    - If returning anything but `.indefinite`, further calls will go to `reEvaluateScope`
    ///
    /// If the block is setting any scope variable values, assign them to the corresponding key previously
    /// reported in `scopeVariables` - any variable keys not previously reported in that property will
    /// be ignored and not available inside the block's scope.
    mutating func evaluateNilScope(_ params: ParameterValues,
                                   _ variables: inout [String: LeafData]) -> ScopeCount

    /// Re-entrant point for `LeafBlock`s that previously reported a finite scope count
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount
}


/// An object that can be chained to other `ChainedBlock` objects
///
/// - Ex: `#if(): #elseif(): #else: #endif`
/// When evaluating, the first block to return a concrete `variables` dictionary (even empty) will have its
/// block evaluated and further blocks in the chain will be immediately discarded.
public protocol ChainedBlock: LeafBlock {
    static var chainsTo: [ChainedBlock.Type] { get }
    static var chainAccepts: [ChainedBlock.Type] { get }
}

/// A `RawBlock` is a specialized `LeafBlock` that is provided raw ByteBuffer input.
///
/// It may optionally process in another language and maintain its own state.
public protocol RawBlock: LeafFunction {
    /// If this raw handler is stateful
    /// - False if this handler makes no attempts to manage the state of its contents.
    /// - True if it should be signaled when the next raw block is the same type
    static var stateful: Bool { get }
    
    /// If the raw handler should be recalled after it has been provided its block's serialized contents
    static var recall: Bool { get }
    
    /// Generate a `.raw` block
    /// - Parameters:
    ///   - parameters: The parameters this object requires at parse time
    ///   - data: Raw ByteBuffer input, if any exists yet
    ///   - encoding: Encoding of the incoming string.
    static func instantiate(data: ByteBuffer?,
                            encoding: String.Encoding) -> RawBlock
    
    /// Adherent must be able to provide a serialized view of itself in entirety
    ///
    /// `valid` shall be semantic for the block type. An HTML raw block might report as follows
    /// ```
    /// <div></div>   // true (valid as an encapsulated block)
    /// <div><span>   // nil (indefinite)
    /// <div></span>  // false (always invalid)
    var serialized: (buffer: ByteBuffer, valid: Bool?) { get }
    
    /// Optional error information if the handler is stateful which LeafKit may choose to report/log.
    var error: String? { get }
    
    /// Append a second block to this one.
    ///
    /// If the second block is the same type, adherent should take care of maintaining state as necessary.
    /// If it isn't of the same type, adherent may assume it's a completed RawBlock and access
    /// `block.serialized` to obtain a `ByteBuffer` to append
    mutating func append(_ block: inout RawBlock) throws
    
    mutating func append(_ buffer: inout ByteBuffer) throws
    
    mutating func append(_ data: LeafData)
    
    /// Bytes in the raw buffer
    var byteCount: UInt64 { get }
    var contents: String { get }
}

internal protocol MetaBlock: LeafBlock {
    static var form: MetaBlockForm { get }
}

internal enum MetaBlockForm: Int, Hashable {
    case rawSwitch
    case define
    case evaluate
    case inline
}

// MARK: - Default Conformances

/// Default implementations for typical `LeafBlock`s
public extension LeafBlock {  
    /// Most blocks are not evaluable
    static var returns: Set<LeafDataType> { [.void] }
    
    /// Default implementation of LeafFunction.evaluate()
    func evaluate(_ parameters: ParameterValues) -> LeafData {
        if Self.evaluable { __MajorBug("LeafBlock called as a function: implement `evaluate`") }
        else { __MajorBug("Catachall default implementation for non-evaluable block") }
    }
}

/// Default implementations for typical `RawBlock`s
public extension RawBlock {
    /// Most `RawBlocks` won't have a parse signature
//    static var parseSignatures: [String: [ParseParameter]]? { nil }
    /// Most blocks are not evaluable
    static var returns: Set<LeafDataType> { [.void] }

    static var invariant: Bool { true }
    static var callSignature: [CallParameter] {[]}
//
//    var scopeVariables: [String]? { nil }
//
//    func evaluateScope(_ params: ParameterValues) -> ScopeValue { .once() }
    
    /// RawBlocks will never be called with evaluate
    func evaluate(_ params: ParameterValues) -> LeafData { .trueNil }
}

extension ChainedBlock {
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount { __MajorBug("ChainedBlocks only called once") }
}

extension MetaBlock {
    static var parseSignatures: [String: [ParseParameter]]? { __MajorBug("MetaBlock") }
    static var evaluable: Bool  { false }
    static func instantiate(_ signature: String?, _ params: [String]) throws -> Self  { __MajorBug("MetaBlock") }
    
    var form: MetaBlockForm { Self.form }
    
    var scopeVariables: [String]? { nil }
    mutating func evaluateNilScope(_ params: ParameterValues,  _ variables: inout [String: LeafData]) -> ScopeCount  { .once }
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> ScopeCount { __MajorBug("Metablocks only called once") }
}
