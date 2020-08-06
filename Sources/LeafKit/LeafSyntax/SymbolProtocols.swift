// MARK: Subject to change prior to 1.0.0 release
// MARK: -

/// A `SymbolMap` provides a Dictionary of concrete `LeafData` available for a symbolic key
typealias SymbolMap = [LeafVariable: LeafData]

internal extension Dictionary where Key == LeafVariable, Value == LeafData {
    func match(_ variable: LeafVariable) -> LeafData {
        self[variable] ?? self[variable.contextualized] ?? .trueNil
    }
}

/// Adhere to `SymbolContainer`to provide generic property/method that allow resolution by Leaf
internal protocol LeafSymbol: SymbolPrintable {
    /// A `SymbolicBox` allows generic returning from resolve to soft-resolve
    ///
    /// Only one of `symbol` and `data` should be non-nil:
    /// - An return of `Self` to provide the same level of object if it cannot yet fully resolve to data
    ///   (either due to lack of needed symbols or because some data is variant), or
    /// - `LeafData` if it is fully resolvable, providing the evaluated return.
    /// - Both values nil should *always and only* indicate that the object *cannot possibly* be resolved.
    typealias SymbolicBox = (symbol: Self?, data: LeafData?)
    
    /// If the symbol is fully resolved
    ///
    /// An unresolved symbol is equivalent to nil at the time of inquiry, but *may* be resolvable.
    var resolved: Bool { get }
    /// If the symbol can be safely evaluated at arbitrary times
    ///
    /// A *variant* symbol is something that may produce different results *for the same input* (eg Date())
    var invariant: Bool { get }
    /// Any variables this symbol requires to fully resolve.
    var symbols: Set<LeafVariable> { get }
    
    /// Attempt to resolve with provided symbols.
    ///
    /// Always returns the same type of object,
    func resolve(_ symbols: SymbolMap) -> Self
    /// Force attempt to evalute the symbol with provided symbols
    ///
    /// Atomic symbols should always result in `LeafData` or`.trueNil` if unevaluable due to lack
    /// of needed symbols, or if a non-atomic (eg, `Tuple` or a non-calculation `Expression`)
    func evaluate(_ symbols: SymbolMap) -> LeafData
}

/// Provide `description` and `short` printable representations for convenience
internal protocol SymbolPrintable: CustomStringConvertible {
    /// - Ex: `bool(true)` or `raw("This is a raw block")` - description should be descriptive
    var description: String { get }
    /// - Ex: `true` or `raw(19)` - short form should be descriptive but succinct
    var short: String { get }
}
