/// A `LeafFunction` that additionally can be used on a method on concrete `LeafData` types
///
/// Example: `#(aStringVariable.hasPrefix("prefix")`
/// The first parameter of the `.callSignature` provides the types the method can operate on. The method
/// will still be called using `LeafFunction.evaluate`, with the first parameter being the operand.
public protocol LeafMethod: LeafFunction {
    /// When true, `mutatingEvalutate` rather than `evaluate` will be called)
    static var mutating: Bool { get }
    
    /// If the method is marked `mutating`, return non-nil for `mutate` to the value the operand should
    /// now hold, or nil if it has not changed. Always return `result`
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LeafData?, result: LeafData)
}

public extension LeafMethod {
    static var mutating: Bool { false }
    
    func mutatingEvaluate(_ params: LeafCallValues) -> (mutate: LeafData?, result: LeafData) {
        (nil, .error("")) }
}

public protocol LeafMutatingMethod: LeafMethod {}

public extension LeafMutatingMethod {
    static var mutating: Bool { true }
    static var invariant: Bool { false }
    
    func evaluate(_ params: LeafCallValues) -> LeafData {
        __MajorBug("Non-mutating evaluation called on mutating method") }
}

// MARK: Internal Only

internal extension LeafMethod {
    var mutating: Bool { Self.mutating }
        
    /// Verify that the method's signature isn't empty and passes sanity
    static func _sanity() {
        precondition(!callSignature.isEmpty,
                     "Method must have at least one parameter")
        precondition(callSignature.first!.label == nil,
                     "Method's first parameter cannot be labeled")
        precondition(callSignature.first!.defaultValue == nil,
                     "Method's first parameter cannot be defaulted")
//        precondition(callSignature.first!.optional == false,
//                     "Method's first parameter cannot be optional")
        precondition(mutating ? !invariant : true,
                     "Mutating methods cannot be invariant")
        callSignature._sanity()
    }
}

internal protocol LKMapMethod: LeafMethod, Invariant {}
