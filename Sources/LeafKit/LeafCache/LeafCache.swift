// MARK: LeafCache Protocol Definition
/// Public protocol to adhere to for storing and accessing `LeafAST`s for `LeafRenderer`
public protocol LeafCache {
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop,
        replace: Bool
    ) -> EventLoopFuture<ResolvedDocument>

    func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument?>

    /// - return nil if cache entry didn't exist in the first place, true if purged
    /// - will never return false in this design but should be capable of it
    ///   in the event a cache implements dependency tracking between templates
    func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?>

    func entryCount() -> Int

    var isEnabled : Bool { get set }
    

    // MARK: - Superseded
    // Superseded by insert with remove: parameter - Remove in Leaf-Kit 2?
    @available(*, deprecated, message: "Use insert with replace parameter")
    func insert(
        _ document: ResolvedDocument,
        on loop: EventLoop
    ) -> EventLoopFuture<ResolvedDocument>
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
    ) -> EventLoopFuture<ResolvedDocument>
    {
        if replace { return loop.makeFailedFuture(LeafError(.unsupportedFeature("Protocol adopter does not support replacing entries")))}
        else { return self.insert(documentName, on: loop) }
    }
}
