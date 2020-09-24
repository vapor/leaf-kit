// MARK: Subject to change prior to 1.0.0 release

/// An object that can take `LeafData` parameters and returns a single `LeafData` result
///
/// Example: `#date("now", "YYYY-mm-dd")`
public protocol LeafFunction {
    /// Array of the function's full call parameters
    static var callSignature: [LeafCallParameter] { get }

    /// The concrete type(s) of `LeafData` the function returns
    static var returns: Set<LeafDataType> { get }

    /// Whether the function is invariant (has no potential side effects and always produces the same value given the same input)
    static var invariant: Bool { get }

    /// The actual evaluation function of the `LeafFunction`, which will be called with fully resolved data
    func evaluate(_ params: LeafCallValues) -> LeafData
}

public protocol StringReturn: LeafFunction {}
public extension StringReturn { static var returns: Set<LeafDataType> { .string } }


public protocol VoidReturn: LeafFunction {}
public extension VoidReturn { static var returns: Set<LeafDataType> { .void } }


public protocol BoolReturn: LeafFunction {}
public extension BoolReturn { static var returns: Set<LeafDataType> { .bool } }

public protocol ArrayReturn: LeafFunction {}
public extension ArrayReturn { static var returns: Set<LeafDataType> { .array } }

public protocol DictionaryReturn: LeafFunction {}
public extension DictionaryReturn { static var returns: Set<LeafDataType> { .dictionary } }

public protocol IntReturn: LeafFunction {}
public extension IntReturn { static var returns: Set<LeafDataType> { .int } }

public protocol DoubleReturn: LeafFunction {}
public extension DoubleReturn { static var returns: Set<LeafDataType> { .double } }

public protocol DataReturn: LeafFunction {}
public extension DataReturn { static var returns: Set<LeafDataType> { .data } }

public protocol Invariant: LeafFunction {}
public extension Invariant { static var invariant: Bool { true } }

internal extension LeafFunction {
    var invariant: Bool { Self.invariant }
    var sig: [LeafCallParameter] { Self.callSignature }
}
