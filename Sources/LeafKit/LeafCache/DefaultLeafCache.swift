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
        self.touchLock = .init()
        self.cache = [:]
        self.touches = [:]
    }

    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - loop: `EventLoop` to return futures on
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return
    ///
    /// Use `LeafAST.key` as the 
    public func insert(_ document: Leaf4AST,
                       on loop: EventLoop,
                       replace: Bool = false) -> EventLoopFuture<Leaf4AST> {
        switch insert(document, replace: replace) {
            case .success(let ast): return succeed(ast, on: loop)
            case .failure(let err): return fail(err, on: loop)
        }
    }
    
    /// - Parameters:
    ///   - name: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(_ key: Leaf4AST.Key,
                         on loop: EventLoop) -> EventLoopFuture<Leaf4AST?> {
        succeed(retrieve(key), on: loop)
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(_ key: Leaf4AST.Key,
                       on loop: EventLoop) -> EventLoopFuture<Bool?> {
        guard isEnabled else { return fail(.cachingDisabled, on: loop) }
        return succeed(remove(key), on: loop)
    }
    
    public func touch(_ key: Leaf4AST.Key, _ values: Leaf4AST.TouchValue) {
        if isEnabled { touchLock.withLockVoid { touches[key]!.append(values) } }
    }
    
    // MARK: - Internal Only
    
    internal let lock: Lock
    internal var cache: [Leaf4AST.Key: Leaf4AST]
    
    internal let touchLock: Lock
    internal var touches: [Leaf4AST.Key: ContiguousArray<Leaf4AST.TouchValue>]
    
    /// Blocking file load behavior
    internal func insert(_ document: Leaf4AST,
                         replace: Bool) -> Result<Leaf4AST, LeafError> {
        guard isEnabled else { return .failure(leafError(.cachingDisabled)) }
        /// Blind failure if caching is disabled
        var e: Bool = false
        lock.withLockVoid {
            if replace || !cache.keys.contains(document.key) {
                cache[document.key] = document
            } else { e = true }
        }
        touchLock.withLockVoid {
            touches[document.key] = .init()
            touches[document.key]?.reserveCapacity(4)
        }
        guard !e else { return .failure(leafError(.keyExists(document.name))) }
        return .success(document)
    }
    
    /// Blocking file load behavior
    internal func retrieve(_ key: Leaf4AST.Key) -> Leaf4AST? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard cache.keys.contains(key) else { return nil }
        touchLock.withLockVoid {
            while let touch = touches[key]!.popLast() {
                cache[key]!.touch(values: touch)
            }
        }
        return cache[key]
    }
    
    /// Blocking file load behavior
    internal func remove(_ key: Leaf4AST.Key) -> Bool? {
        touchLock.withLockVoid { touches.removeValue(forKey: key) }
        return lock.withLock {
            cache.removeValue(forKey: key) != nil ? true : nil
        }
    }
}
