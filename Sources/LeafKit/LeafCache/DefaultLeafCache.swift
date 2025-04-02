import NIOCore
import NIOConcurrencyHelpers

public final class DefaultLeafCache: SynchronousLeafCache {
    // MARK: - Public - `LeafCache` Protocol Conformance
    
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool = true
    /// Current count of cached documents
    public var count: Int {
        self.lock.withLock { self.cache.count }
    }

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
        guard self.isEnabled else {
            return loop.makeSucceededFuture(document)
        }

        return self.lock.withLock {
            // return an error if replace is false and the document name is already in cache
            switch (self.cache.keys.contains(document.name), replace) {
                case (true, false):
                    return loop.makeFailedFuture(LeafError(.keyExists(document.name)))
                default:
                    self.cache[document.name] = document
            }
            return loop.makeSucceededFuture(document)
        }
    }
    
    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(
        documentName: String,
        on loop: any EventLoop
    ) -> EventLoopFuture<LeafAST?> {
        guard self.isEnabled else {
            return loop.makeSucceededFuture(nil)
        }
        return self.lock.withLock {
            loop.makeSucceededFuture(self.cache[documentName])
        }
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
        guard self.isEnabled else {
            return loop.makeFailedFuture(LeafError(.cachingDisabled))
        }

        return self.lock.withLock {
            guard self.cache[documentName] != nil else {
                return loop.makeSucceededFuture(nil)
            }
            self.cache[documentName] = nil
            return loop.makeSucceededFuture(true)
        }
    }
    
    // MARK: - Internal Only
    
    let lock: NIOLock
    var cache: [String: LeafAST]
    
    /// Blocking file load behavior
    func retrieve(documentName: String) throws -> LeafAST? {
        guard self.isEnabled else {
            throw LeafError(.cachingDisabled)
        }
        return try self.lock.withLock {
            guard let result = self.cache[documentName] else {
                throw LeafError(.noValueForKey(documentName))
            }
            return result
        }
    }
}
