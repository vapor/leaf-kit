/// A function, method, or block that desires access to application-provided unsafe data stores may
/// optionally adhere to `LeafUnsafeFunction` to be provided with a dictionary of data that was
/// previously registered to the `LeafRenderer` in configuration prior to it being called via any relevant
/// evaluation function appropriate for the type. If no such dictionary was registered or user has configured
/// LeafKit to disallow unsafe object access to custom tags, value will be nil.
///
/// Any structures so passed *may be reference types* if so configured - no guarantees are made, and
/// using such an unsafe entity on a non-threadsafe stored value may cause runtime issues.
public protocol LeafUnsafeEntity: LeafFunction {
    var unsafeObjects: UnsafeObjects? { get set }
}

public typealias UnsafeObjects = [String: Any]

public extension LeafUnsafeEntity {
    static var invariant: Bool { false }
}
