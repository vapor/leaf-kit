

/// A `LeafFunction` that additionally can be used on a method on concrete `LeafData` types.
///
/// Example: `#(aStringVariable.hasPrefix("prefix")`
/// The first parameter of the `.callSignature` provides the types the method can operate on. The method
/// will still be called using `LeafFunction.evaluate`, with the first parameter being the operand.
///
/// Has the potential to mutate the first parameter it is passed; must either be mutating or non-mutating (not both).
///
/// Convenience protocols`Leaf(Non)MutatingMethod`s preferred for adherence as they provide default
/// implementations for the enforced requirements of those variations.
public protocol LeafMethod: LeafFunction {}

/// A `LeafMethod` that does not mutate its first parameter value.
public protocol LeafNonMutatingMethod: LeafMethod {}

/// A `LeafMethod` that may potentially mutate its first parameter value.
public protocol LeafMutatingMethod: LeafMethod {
    /// Return non-nil for `mutate` to the value the operand should now hold, or nil if it has not changed. Always return `result`
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: Optional<LeafData>, result: LeafData)
}

public extension LeafMutatingMethod {
    /// Mutating methods are inherently always variant
    static var invariant: Bool { false }
    
    /// Mutating methods will never be called with the normal `evaluate` call
    func evaluate(_ params: LeafCallValues) -> LeafData {
        .error(internal: "Non-mutating evaluation on mutating method") }
}

// MARK: Internal Only

internal extension LeafMethod {
    var mutating: Bool { self as? LeafMutatingMethod != nil }
}
internal protocol LKMapMethod: LeafNonMutatingMethod, Invariant {}

internal protocol BoolParam: LeafFunction {}
internal extension BoolParam { static var callSignatures: [LeafCallParameter] { [.bool] } }

internal protocol IntParam: LeafFunction {}
internal extension IntParam { static var callSignatures: [LeafCallParameter] { [.int] } }

internal protocol DoubleParam: LeafFunction {}
internal extension DoubleParam { static var callSignatures: [LeafCallParameter] { [.double] } }

internal protocol StringParam: LeafFunction {}
internal extension StringParam { static var callSignature: [LeafCallParameter] { [.string] } }

internal protocol StringStringParam: LeafFunction {}
internal extension StringStringParam { static var callSignature: [LeafCallParameter] { [.string, .string] } }

internal protocol DictionaryParam: LeafFunction {}
internal extension DictionaryParam { static var callSignature: [LeafCallParameter] { [.dictionary] } }

internal protocol ArrayParam: LeafFunction {}
internal extension ArrayParam { static var callSignature: [LeafCallParameter] { [.array] } }

internal protocol CollectionsParam: LeafFunction {}
internal extension CollectionsParam { static var callSignature: [LeafCallParameter] { [.collections] } }
