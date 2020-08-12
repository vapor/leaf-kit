// MARK: Stable?!!

import NIOConcurrencyHelpers

public final class DefaultLeafCache: LKSynchronousCache {
    /// Initializer
    public init() {
        self.locks = (.init(), .init())
        self.cache = [:]
        self.touches = [:]
    }
    
    // MARK: - Public - LeafCache Conformance
    
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool {
        get { locks.c.withLock { _isEnabled } }
        set { locks.c.withLock { _isEnabled = newValue } }
    }
    
    /// Current count of cached documents
    public var count: Int { locks.t.withLock { touches.count } }

    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - loop: `EventLoop` to return futures on
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return
    ///
    /// Use `LeafAST.key` as the 
    public func insert(_ document: LeafAST,
                       on loop: EventLoop,
                       replace: Bool = false) -> EventLoopFuture<LeafAST> {
        switch insert(document, replace: replace) {
            case .success(let ast): return succeed(ast, on: loop)
            case .failure(let err): return fail(err, on: loop)
        }
    }
    
    /// - Parameters:
    ///   - name: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(_ key: LeafASTKey,
                         on loop: EventLoop) -> EventLoopFuture<LeafAST?> {
        succeed(retrieve(key), on: loop)
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(_ key: LeafASTKey,
                       on loop: EventLoop) -> EventLoopFuture<Bool?> {
        guard _isEnabled else { return fail(.cachingDisabled, on: loop) }
        return succeed(remove(key), on: loop)
    }
    
    public func touch(_ key: LeafASTKey, _ values: LeafASTTouch) {
        if _isEnabled { locks.t.withLockVoid { touches[key]!.append(values) } }
    }
    
    // MARK: - Internal - LKSynchronousCache
    
    /// Blocking file load behavior
    func insert(_ document: LeafAST, replace: Bool) -> Result<LeafAST, LeafError> {
        guard _isEnabled else { return .failure(leafError(.cachingDisabled)) }
        /// Blind failure if caching is disabled
        var e: Bool = false
        locks.c.withLockVoid {
            if replace || !cache.keys.contains(document.key) {
                cache[document.key] = document
            } else { e = true }
        }
        locks.t.withLockVoid {
            touches[document.key] = .init()
            touches[document.key]?.reserveCapacity(4)
        }
        guard !e else { return .failure(leafError(.keyExists(document.name))) }
        return .success(document)
    }
    
    /// Blocking file load behavior
    func retrieve(_ key: LeafASTKey) -> LeafAST? {
        guard _isEnabled else { return nil }
        locks.c.lock()
        defer { locks.c.unlock() }
        guard cache.keys.contains(key) else { return nil }
        locks.t.lock()
        defer { locks.t.unlock() }
        while let touch = touches[key]!.popLast() { cache[key]!.touch(values: touch) }
        return cache[key]
    }
    
    /// Blocking file load behavior
    func remove(_ key: LeafASTKey) -> Bool? {
        if locks.t.withLock({ touches.removeValue(forKey: key) == nil }) { return nil }
        locks.c.withLockVoid { cache.removeValue(forKey: key) }
        return true
    }
    
    // MARK: - Stored Properties - Private Only
    private var _isEnabled: Bool = true
    private let locks: (c: Lock, t: Lock)
    /// NOTE: internal read-only purely for test access validation - not assured
    private(set) var cache: [LeafASTKey: LeafAST]
    private var touches: [LeafASTKey: ContiguousArray<LeafASTTouch>]
}
