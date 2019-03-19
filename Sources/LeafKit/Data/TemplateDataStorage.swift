import Foundation

internal enum LeafDataStorage {
    /// A `Bool`.
    ///
    ///     true
    ///
    case bool(Bool)

    /// A `String`.
    ///
    ///     "hello"
    ///
    case string(String)

    /// An `Int`.
    ///
    ///     42
    ///
    case int(Int)

    /// A `Double`.
    ///
    ///     3.14
    ///
    case double(Double)

    /// `Data` blob.
    ///
    ///     Data([0x72, 0x73])
    ///
    case data(Data)

    /// A nestable `[String: LeafData]` dictionary.
    case dictionary([String: LeafData])

    /// A nestable `[LeafData]` array.
    case array([LeafData])

    /// A lazily-resolvable `LeafData`.
    case lazy(() -> (LeafData))

    /// Null.
    case null
}
