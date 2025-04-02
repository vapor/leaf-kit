import NIOConcurrencyHelpers
import NIOCore

public actor DefaultLeafCache: LeafCache {
    // MARK: - Public - `LeafCache` Protocol Conformance

    /// Global setting for enabling or disabling the cache
    private(set) public var isEnabled: Bool = true
    /// Current count of cached documents
    public var count: Int { self.cache.count }

    /// Initializer
    public init() {
        self.cache = [:]
    }

    public func toggleEnabled() {
        self.isEnabled = !isEnabled
    }

    /// - Parameters:
    ///   - document: The `LeafAST` to store
    ///   - loop: `EventLoop` to return futures on
    ///   - replace: If a document with the same name is already cached, whether to replace or not.
    /// - Returns: The document provided as an identity return
    public func insert(_ document: LeafAST, replace: Bool = false) async throws -> LeafAST {
        // future fails if caching is enabled
        guard self.isEnabled else {
            return document
        }

        // return an error if replace is false and the document name is already in cache
        switch (self.cache.keys.contains(document.name), replace) {
        case (true, false):
            throw LeafError(.keyExists(document.name))
        default:
            self.cache[document.name] = document
        }
        return document
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to return
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<LeafAST?>` holding the `LeafAST` or nil if no matching result
    public func retrieve(documentName: String) async throws -> LeafAST? {
        guard self.isEnabled else {
            return nil
        }
        return self.cache[documentName]
    }

    /// - Parameters:
    ///   - documentName: Name of the `LeafAST`  to try to purge from the cache
    ///   - loop: `EventLoop` to return futures on
    /// - Returns: `EventLoopFuture<Bool?>` - If no document exists, returns nil. If removed,
    ///     returns true. If cache can't remove because of dependencies (not yet possible), returns false.
    public func remove(_ documentName: String) async throws -> Bool? {
        guard self.isEnabled else {
            throw LeafError(.cachingDisabled)
        }

        guard self.cache[documentName] != nil else {
            return nil
        }
        self.cache[documentName] = nil
        return true
    }

    // MARK: - Internal Only
    var cache: [String: LeafAST]

    /// Blocking file load behavior
    func retrieve(documentName: String) throws -> LeafAST? {
        guard self.isEnabled else {
            throw LeafError(.cachingDisabled)
        }
        guard let result = self.cache[documentName] else {
            throw LeafError(.noValueForKey(documentName))
        }
        return result
    }
}
