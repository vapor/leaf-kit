/// A `LeafCache` that provides certain blocking methods for non-future access to the cache
///
/// Adherents *MUST* be thread-safe and *SHOULD NOT* be blocking simply to avoid futures -
/// only adhere to this protocol if using futures is needless overhead. Currently restricted to LeafKit internally.
internal protocol LKSynchronousCache: LeafCache {
    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - replace: If a document with the same name is already cached, whether to replace or not
    /// - Returns: The document provided as an identity return when success, or a failure error
    func insert(_ document: LeafAST, replace: Bool) -> Result<LeafAST, LeafError>

    /// - Parameter key: Name of the `LeafAST` to try to return
    /// - Returns: The requested `LeafAST` or nil if not found
    func retrieve(_ key: LeafASTKey) -> LeafAST?

    /// - Parameter key: Name of the `LeafAST`  to try to purge from the cache
    /// - Returns: `Bool?` If removed,  returns true. If cache can't remove because of dependencies
    ///      (not yet possible), returns false. Nil if no such cached key exists.
    func remove(_ key: LeafASTKey) -> Bool?
    
    func info(for key: LeafASTKey) -> LeafASTInfo?
}
