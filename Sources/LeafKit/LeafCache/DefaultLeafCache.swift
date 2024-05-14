import NIOConcurrencyHelpers
import NIO

/// `@unchecked Sendable` because uses locks to guarantee Sendability.
public final class DefaultLeafCache: SynchronousLeafCache, @unchecked Sendable {
    // MARK: - Public - `LeafCache` Protocol Conformance

    var __isEnabled = true
    /// Global setting for enabling or disabling the cache
    public var _isEnabled: Bool {
        get {
            self.lock.withLock {
                self.__isEnabled
            }
        }
        set(newValue) {
            self.lock.withLock {
                self.__isEnabled = newValue
            }
        }
    }
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool {
        get {
            self._isEnabled
        }
        set(newValue) {
            self._isEnabled = newValue
        }
    }
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
        on loop: EventLoop,
        replace: Bool = false
    ) -> EventLoopFuture<LeafAST> {
        self.lock.withLock {
            // future fails if caching is enabled
            guard __isEnabled else { return loop.makeSucceededFuture(document) }
            // return an error if replace is false and the document name is already in cache
            switch (self.cache.keys.contains(document.name),replace) {
            case (true, false): return loop.makeFailedFuture(LeafError(.keyExists(document.name)))
            default: self.cache[document.name] = document
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
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST?> {
        self.lock.withLock {
            guard __isEnabled == true else { return loop.makeSucceededFuture(nil) }
            return loop.makeSucceededFuture(self.cache[documentName])
        }
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
        self.lock.withLock {
            guard __isEnabled == true else { return loop.makeFailedFuture(LeafError(.cachingDisabled)) }
            guard self.cache[documentName] != nil else { return loop.makeSucceededFuture(nil) }
            self.cache[documentName] = nil
            return loop.makeSucceededFuture(true)
        }
    }
    
    // MARK: - Internal Only
    
    internal let lock: NIOLock
    internal var cache: [String: LeafAST]
    
    /// Blocking file load behavior
    internal func retrieve(documentName: String) throws -> LeafAST? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard __isEnabled == true else { throw LeafError(.cachingDisabled) }
        let result = self.cache[documentName]
        guard result != nil else { throw LeafError(.noValueForKey(documentName)) }
        return result
    }
}
