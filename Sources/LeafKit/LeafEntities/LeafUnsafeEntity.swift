/// A function, method, or block that requires access to application-provided unsafe data stores may
/// optionally adhere to `LeafUnsafeFunction` to be provided with a dictionary of data that was
/// previously registered to the `LeafRenderer` in configuration prior to it being called via any relevant
/// evaluation function appropriate for the type. If no such dictionary was registered, value will be nil.
/// Any structures so passed *may be reference types* if so configured - no guarantees are made, and
/// using such an unsafe entity on a non-threadsafe stored value may cause runtime issues.
public protocol LeafUnsafeEntity {
    var externalObjects: ExternalObjects? { get set }
}

public typealias ExternalObjects = [AnyHashable: Any]
