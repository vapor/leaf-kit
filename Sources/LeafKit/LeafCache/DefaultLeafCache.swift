import NIOConcurrencyHelpers

/// The default implementation of `LeafCache`
public final class DefaultLeafCache {
    /// Initializer
    public init() {
        self.locks = (.init(), .init())
        self.cache = [:]
        self.touches = [:]
    }
    
    // MARK: - Stored Properties - Private Only
    private var _isEnabled: Bool = true
    private let locks: (cache: RWLock, touch: RWLock)
    /// NOTE: internal read-only purely for test access validation - not assured
    private(set) var cache: [LeafASTKey: LeafAST]
    private var touches: [LeafASTKey: LeafASTTouch]
}

// MARK: - Public - LeafCache
extension DefaultLeafCache: LeafCache {
    /// Global setting for enabling or disabling the cache
    public var isEnabled: Bool {
        get { locks.cache.readWithLock { _isEnabled } }
        set { locks.cache.writeWithLock { _isEnabled = newValue } }
    }

    public var count: Int { locks.cache.readWithLock { cache.count } }
    
    public var isEmpty: Bool { locks.cache.readWithLock { cache.isEmpty } }
    
    public var keys: Set<LeafASTKey> { .init(locks.cache.readWithLock { cache.keys }) }

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

    public func touch(_ key: LeafASTKey,
                      _ values: LeafASTTouch) {
        if _isEnabled { locks.touch.writeWithLock { touches[key]!.aggregate(values: values) } }
    }
    
    public func info(for key: LeafASTKey,
                     on loop: EventLoop) -> EventLoopFuture<LeafASTInfo?> {
        succeed(info(for: key), on: loop)
    }
    
    public func dropAll() {
        locks.cache.writeWithLock {
            locks.touch.writeWithLock {
                cache.removeAll()
                touches.removeAll()
            }
        }
    }
}

// MARK: - Internal - LKSynchronousCache
extension DefaultLeafCache: LKSynchronousCache {
    /// Blocking file load behavior
    func insert(_ document: LeafAST, replace: Bool) -> Result<LeafAST, LeafError> {
        guard _isEnabled else { return .failure(err(.cachingDisabled)) }
        /// Blind failure if caching is disabled
        var e: Bool = false
        locks.cache.writeWithLock {
            if replace || !cache.keys.contains(document.key) {
                cache[document.key] = document
                locks.touch.writeWithLock { touches[document.key] = .empty }
            } else { e = true }
        }
        guard !e else { return .failure(err(.keyExists(document.name))) }
        return .success(document)
    }

    /// Blocking file load behavior
    func retrieve(_ key: LeafASTKey) -> LeafAST? {
        guard _isEnabled else { return nil }
        return locks.cache.readWithLock {
            guard cache.keys.contains(key) else { return nil }
            locks.touch.writeWithLock {
                if touches[key]!.count >= 128,
                   let touch = touches.updateValue(.empty, forKey: key) {
                    cache[key]!.touch(values: touch) }
            }
            return cache[key]
        }
    }

    /// Blocking file load behavior
    func remove(_ key: LeafASTKey) -> Bool? {
        if locks.touch.writeWithLock({ touches.removeValue(forKey: key) == nil }) { return nil }
        locks.cache.writeWithLock { _ = cache.removeValue(forKey: key) }
        return true
    }
    
    func info(for key: LeafASTKey) -> LeafASTInfo? {
        locks.cache.readWithLock {
            guard cache.keys.contains(key) else { return nil }
            locks.touch.writeWithLock {
                if let touch = touches.updateValue(.empty, forKey: key) {
                    cache[key]!.touch(values: touch) }
            }
            return cache[key]!.info
        }
    }
}
