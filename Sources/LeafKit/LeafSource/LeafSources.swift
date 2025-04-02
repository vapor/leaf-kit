import NIOCore
import NIOConcurrencyHelpers

/// An opaque object holding named `LeafSource` adherants specifying a default search order.
///
/// This object is `public` solely for convenience in reading the currently configured state.
///
/// Once registered, the `LeafSource` objects can not be accessed or modified - they *must* be
/// fully configured prior to registering with the instance of `LeafSources`
/// - `LeafSource` objects are registered with an instance of this class - this should *only* be done
///     prior to use by `LeafRenderer`.
/// - `.all` provides a `Set` of the `String`keys for all sources registered with the instance
/// - `.searchOrder` provides the keys of sources that an unspecified template request will search.
public final class LeafSources: Sendable {
    // MARK: - Public
    
    /// All available `LeafSource`s of templates
    public var all: Set<String> {
        self.lock.withLock { .init(self.sources.keys) }
    }
    /// Configured default implicit search order of `LeafSource`'s
    public var searchOrder: [String] {
        self.lock.withLock { self.order }
    }

    public init() {
        self.sources = [:]
        self.order = []
    }
    
    /// Register a `LeafSource` as `key`
    /// - Parameters:
    ///   - key: Name for the source; at most one may be registered without a name
    ///   - source: A fully configured `LeafSource` object
    ///   - searchable: Whether the source should be added to the default search path
    /// - Throws: Attempting to overwrite a previously named source is not permitted
    public func register(
        source key: String = "default",
        using source: any LeafSource,
        searchable: Bool = true
    ) throws {
        try self.lock.withLock {
            guard !self.sources.keys.contains(key) else {
                throw LeafError(.unknownError("Can't replace source at \(key)"))
            }
            self.sources[key] = source
            if searchable {
                self.order.append(key)
            }
        }
    }
    
    /// Convenience for initializing a `LeafSources` object with a single `LeafSource`
    /// - Parameter source: A fully configured `LeafSource`
    /// - Returns: Configured `LeafSource` instance
    public static func singleSource(_ source: any LeafSource) -> LeafSources {
        let sources = LeafSources()
        try! sources.register(using: source)
        return sources
    }
    
    // MARK: - Internal Only

    // Note: nonisolated(unsafe) is safe because these are protected by the lock
    private(set) nonisolated(unsafe) var sources: [String: any LeafSource]
    private nonisolated(unsafe) var order: [String]
    private let lock: NIOLock = .init()
    
    /// Locate a template from the sources; if a specific source is named, only try to read from it. Otherwise, use the specified search order
    func find(template: String, in source: String? = nil, on eventLoop: any EventLoop) throws -> EventLoopFuture<(String, ByteBuffer)> {
        var keys: [String]
        
        switch source {
        case .none:
            keys = self.searchOrder
        case .some(let source):
            if all.contains(source) {
                keys = [source]
            } else {
                throw LeafError(.illegalAccess("Invalid source \(source) specified"))
            }
        }
        guard !keys.isEmpty else {
            throw LeafError(.illegalAccess("No searchable sources exist"))
        }

        return self.searchSources(t: template, on: eventLoop, s: keys)
    }
    
    private func searchSources(t: String, on eL: any EventLoop, s: [String]) -> EventLoopFuture<(String, ByteBuffer)> {
        guard !s.isEmpty else {
            return eL.makeFailedFuture(LeafError(.noTemplateExists(t)))
        }
        var more = s
        let key = more.removeFirst()
        let source = self.lock.withLock {
            self.sources[key]!
        }

        do {
            let file = try source.file(template: t, escape: true, on: eL)
            // Hit the file - return the combined tuple
            return eL.makeSucceededFuture(key).and(file).flatMapError { [more] _ in
                // Or move onto the next one if this source can't get the file
                return self.searchSources(t: t, on: eL, s: more)
            }
        } catch {
            // If the thrown error is illegal access, fail immediately
            if let e = error as? LeafError,
               case .illegalAccess(_) = e.reason
            {
                return eL.makeFailedFuture(e)
            } else {
                // Or move onto the next one
                return self.searchSources(t: t, on: eL, s: more)
            }
        }
    }
}
