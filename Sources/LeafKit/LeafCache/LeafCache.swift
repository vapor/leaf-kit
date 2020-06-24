// MARK: Subject to change prior to 1.0.0 release
// MARK: -

/// `LeafCache` provides blind storage for compiled `LeafAST` objects.
///
/// The stored `LeafAST`s may or may not be fully renderable templates, and generally speaking no
/// attempts should be made inside a `LeafCache` adherent to make any changes to the stored document.
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
    /// - Returns: The document provided as an identity return
    func insert(
        _ document: LeafAST,
        on loop: EventLoop,
        replace: Bool
    ) -> EventLoopFuture<LeafAST>
    
    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST?>

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?>

    // MARK: - Deprecated
    // Superseded by insert with remove: parameter - Remove in Leaf-Kit 2?
    @available(*, deprecated, message: "Use insert with replace parameter")
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument>
}

/// A `LeafCache` that provides certain blocking methods for non-future access to the cache
///
/// Adherents *MUST* be thread-safe and *SHOULD NOT* be blocking simply to avoid futures -
/// only adhere to this protocol if using futures is needless overhead
internal protocol BlockingLeafCache: LeafCache {
    func load(documentName: String) -> LeafAST?
}

// MARK: - LeafCache default implementations for older adherants
extension LeafCache {
    /// default implementation of remove to avoid breaking custom LeafCache adopters
    func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?>
    {
        return loop.makeFailedFuture(
            LeafError(.unsupportedFeature("Protocol adopter does not support removing entries")))
    }

    /// default implementation of remove to avoid breaking custom LeafCache adopters
    ///     throws an error if used with replace == true
    func insert(
        _ documentName: String,
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<LeafAST>
    {
        if replace { return loop.makeFailedFuture(LeafError(.unsupportedFeature("Protocol adopter does not support replacing entries")))}
        else { return self.insert(documentName, on: loop) }
    }
}
