// MARK: Stable?!!
// MARK: -

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
    var isEnabled : Bool { get set }
    /// Current count of cached documents
    var count: Int { get }
    
    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - loop: `EventLoop` to return futures on
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return (or a failed future if it can't be inserted)
    func insert(_ document: LeafAST,
                on loop: EventLoop,
                replace: Bool) -> EventLoopFuture<LeafAST>
    
    /// - Parameters:
    ///   - key: `LeafAST.key`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    func retrieve(_ key: LeafASTKey,
                  on loop: EventLoop) -> EventLoopFuture<LeafAST?>

    /// - Parameters:
    ///   - key: `LeafAST.key`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    func remove(_ key: LeafASTKey,
                on loop: EventLoop) -> EventLoopFuture<Bool?>
    
    /// Touch a stored AST with an execution time
    func touch(_ key: LeafASTKey,
               _ value: LeafASTTouch)
}
