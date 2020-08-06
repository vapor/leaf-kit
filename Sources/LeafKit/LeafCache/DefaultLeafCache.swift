// MARK: Subject to change prior to 1.0.0 release
// MARK: -


import NIOConcurrencyHelpers

public final class DefaultLeafCache: SynchronousLeafCache {
    // MARK: - Public - `LeafCache` Protocol Conformance
    
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool = true
    /// Current count of cached documents
    public var count: Int { lock.withLock { cache.count } }
    
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
    public func insert(_ document: Leaf4AST,
                       on loop: EventLoop,
                       replace: Bool = false) -> EventLoopFuture<Leaf4AST> {
        var e: Bool = false
        if isEnabled {
            lock.lock()
            if replace || !cache.keys.contains(document.key) {
                cache[document.key] = document
            } else { e = true }
            lock.unlock()
        }
        guard !e else { return fail(.keyExists(document.key), on: loop) }
        return succeed(document, on: loop)
    }
    
    /// - Parameters:
    ///   - name: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(_ name: String,
                         on loop: EventLoop) -> EventLoopFuture<Leaf4AST?> {
        if !isEnabled { return succeed(nil, on: loop) }
        lock.lock()
        defer { lock.unlock() }
        return succeed(cache[name], on: loop)
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(_ name: String,
                       on loop: EventLoop) -> EventLoopFuture<Bool?> {
        if !isEnabled { return fail(.cachingDisabled, on: loop) }
        lock.lock()
        let state = cache.keys.contains(name)
        if state { cache[name] = nil }
        lock.unlock()
        return succeed(state ? true : nil, on: loop)
    }
    
    // MARK: - Internal Only
    
    internal let lock: Lock
    internal var cache: [String: Leaf4AST]
    
    /// Blocking file load behavior
    internal func insert(_ document: Leaf4AST,
                         replace: Bool) throws -> Leaf4AST? {
        /// Blind failure if caching is disabled
        var e: Bool = false
        if isEnabled {
            lock.lock()
            if replace || !cache.keys.contains(document.key) {
                cache[document.key] = document
            } else { e = true }
            lock.unlock()
        }
        guard !e else { throw leafError(.keyExists(document.key)) }
        return document
    }
    
    /// Blocking file load behavior
    internal func retrieve(_ name: String) throws -> Leaf4AST? {
        guard isEnabled == true else { throw leafError(.cachingDisabled) }
        lock.lock()
        let result = cache[name]
        lock.unlock()
        guard result != nil else { throw leafError(.noValueForKey(name)) }
        return result
    }
    
    /// Blocking file load behavior
    internal func remove(_ name: String) throws -> Bool? {
        if !isEnabled { throw leafError(.cachingDisabled) }
        lock.lock()
        let state = cache.keys.contains(name)
        if state { cache[name] = nil }
        lock.unlock()
        return state ? true : nil
    }
}
