import NIOCore

/// `LeafCache` provides blind storage for compiled `LeafAST` objects.
///
/// The stored `LeafAST`s may or may not be fully renderable templates, and generally speaking no
/// attempts should be made inside a `LeafCache` adherent to make any changes to the stored document.
///
/// All definied access methods to a `LeafCache` adherent must guarantee `EventLoopFuture`-based
/// return values. For performance, an adherent may optionally provide additional, corresponding interfaces
/// where returns are direct values and not future-based by adhering to `SynchronousLeafCache` and
/// providing applicable option flags indicating which methods may be used. This should only used for
/// adherents where the cache store itself is not a bottleneck.
///
/// `LeafAST.name` is to be used in all cases as the key for retrieving cached documents.
public protocol LeafCache {
    /// Global setting for enabling or disabling the cache
    var isEnabled: Bool { get async }
    /// Current count of cached documents
    var count: Int { get async }

    func toggleEnabled() async

    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return (or a failed future if it can't be inserted)
    func insert(_ document: LeafAST, replace: Bool) async throws -> LeafAST

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST` to try to return
    /// - Returns: `LeafAST?` holding the `LeafAST` or nil if no matching result
    func retrieve(documentName: String) async throws -> LeafAST?

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    /// - Returns: `Bool?` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    func remove(_ documentName: String) async throws -> Bool?
}
