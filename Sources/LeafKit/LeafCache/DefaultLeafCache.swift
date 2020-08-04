// MARK: Subject to change prior to 1.0.0 release
// MARK: -


import NIOConcurrencyHelpers

public final class DefaultLeafCache: SynchronousLeafCache {
    // MARK: - Public - `LeafCache` Protocol Conformance
    
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool = true
    /// Current count of cached documents
    public var count: Int { self.lock.withLock { cache.count } }
    
    /// Initializer
    public init() {
        self.lock = .init()
        self.cache = [:]
    }

    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - loop: `EventLoop` to return futures on
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return
    public func insert(
        _ document: Leaf4AST,
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<Leaf4AST> {
        // future fails if caching is enabled
        guard isEnabled else { return loop.makeSucceededFuture(document) }

        lock.lock()
        defer { lock.unlock() }
        // return an error if replace is false and the document name is already in cache
        switch (cache.keys.contains(document.name),replace) {
            case (true, false): return loop.makeFailedFuture(LeafError(.keyExists(document.name)))
            default: cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }
    
    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Leaf4AST?> {
        guard isEnabled == true else { return loop.makeSucceededFuture(nil) }
        lock.lock()
        defer { lock.unlock() }
        return loop.makeSucceededFuture(cache[documentName])
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(
        _ documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<Bool?> {
        guard isEnabled == true else { return loop.makeFailedFuture(LeafError(.cachingDisabled)) }

        lock.lock()
        defer { lock.unlock() }

        guard cache[documentName] != nil else { return loop.makeSucceededFuture(nil) }
        cache[documentName] = nil
        return loop.makeSucceededFuture(true)
    }
    
    // MARK: - Internal Only
    
    internal let lock: Lock
    internal var cache: [String: Leaf4AST]
    
    /// Blocking file load behavior
    internal func retrieve(documentName: String) throws -> Leaf4AST? {
        guard isEnabled == true else { throw LeafError(.cachingDisabled) }
        lock.lock()
        defer { lock.unlock() }
        let result = cache[documentName]
        guard result != nil else { throw LeafError(.noValueForKey(documentName)) }
        return result
    }
}
