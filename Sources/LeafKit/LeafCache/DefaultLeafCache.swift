import NIOConcurrencyHelpers
import NIO

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
        _ document: LeafAST,
        on loop: any EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<LeafAST> {
        // future fails if caching is enabled
        guard isEnabled else { return loop.makeSucceededFuture(document) }

        self.lock.lock()
        defer { self.lock.unlock() }
        // return an error if replace is false and the document name is already in cache
        switch (self.cache.keys.contains(document.name),replace) {
            case (true, false): return loop.makeFailedFuture(LeafError(.keyExists(document.name)))
            default: self.cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }
    
    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(
        documentName: String,
        on loop: any EventLoop
    ) -> EventLoopFuture<LeafAST?> {
        guard isEnabled == true else { return loop.makeSucceededFuture(nil) }
        self.lock.lock()
        defer { self.lock.unlock() }
        return loop.makeSucceededFuture(self.cache[documentName])
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(
        _ documentName: String,
        on loop: any EventLoop
    ) -> EventLoopFuture<Bool?> {
        guard isEnabled == true else { return loop.makeFailedFuture(LeafError(.cachingDisabled)) }

        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.cache[documentName] != nil else { return loop.makeSucceededFuture(nil) }
        self.cache[documentName] = nil
        return loop.makeSucceededFuture(true)
    }
    
    // MARK: - Internal Only
    
    internal let lock: NIOLock
    internal var cache: [String: LeafAST]
    
    /// Blocking file load behavior
    internal func retrieve(documentName: String) throws -> LeafAST? {
        guard isEnabled == true else { throw LeafError(.cachingDisabled) }
        self.lock.lock()
        defer { self.lock.unlock() }
        let result = self.cache[documentName]
        guard result != nil else { throw LeafError(.noValueForKey(documentName)) }
        return result
    }
}
