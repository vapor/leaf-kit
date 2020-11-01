/// `LeafDataGenerator` is a wrapper for passing `LeafDataRepresentable` objects to
/// `LeafRenderer.Context` while deferring conversion to `LeafData` until being accessed
///
/// In all cases, conversion of the `LeafDataRepresentable`-adhering parameter to concrete
/// `LeafData` is deferred until it is actually accessed by `LeafRenderer` (when a template has
/// accessed its value).
///
/// Can be created as either immediate storage of the parameter, or lazy generation of the
/// `LeafDataRepresentable` object itself in order to provide an additional lazy level in the case of items
/// that may have costly conversion procedures (eg, `Encodable` auto-conformance), or to allow a
/// a generally-shared global `.Context` object to be used repeatedly.
public struct LeafDataGenerator {
    /// Produce a generator that immediate stores the parameter
    public static func immediate(_ value: LeafDataRepresentable) -> Self {
        .init(.immediate(value)) }
    
    /// Produce a generator that defers evaluation of the parameter until `LeafRenderer` accesses it
    public static func lazy(_ value: @escaping @autoclosure () -> LeafDataRepresentable) -> Self {
        .init(.lazy(.lazy(f: {value().leafData}, returns: .void))) }
    
    init(_ value: Container) { self.container = value }
    let container: Container
    
    enum Container: LeafDataRepresentable {
        case immediate(LeafDataRepresentable)
        case lazy(LKDContainer)
        
        var leafData: LeafData {
            switch self {
                case .immediate(let ldr): return ldr.leafData
                case .lazy(let lkd): return .init(lkd.evaluate)
            }
        }
    }
}
