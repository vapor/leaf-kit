import NIO
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
///
/// `@unchecked Sendable` because uses locks to guarantee Sendability.
public final class LeafSources: @unchecked Sendable {
    // MARK: - Public
    
    /// All available `LeafSource`s of templates
    public var all: Set<String> { lock.withLock { .init(self.sources.keys) } }
    /// Configured default implicit search order of `LeafSource`'s
    public var searchOrder: [String] { lock.withLock { order } }
    
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
    public func register(source key: String = "default",
                         using source: LeafSource,
                         searchable: Bool = true) throws {
        try lock.withLock {
            guard !sources.keys.contains(key) else { throw "Can't replace source at \(key)" }
            sources[key] = source
            if searchable { order.append(key) }
        }
    }
    
    /// Convenience for initializing a `LeafSources` object with a single `LeafSource`
    /// - Parameter source: A fully configured `LeafSource`
    /// - Returns: Configured `LeafSource` instance
    public static func singleSource(_ source: LeafSource) -> LeafSources {
        let sources = LeafSources()
        try! sources.register(using: source)
        return sources
    }
    
    // MARK: - Internal Only
    internal private(set) var sources: [String: LeafSource]
    private var order: [String]
    private let lock: NIOLock = .init()

    /// Locate a template from the sources; if a specific source is named, only try to read from it. Otherwise, use the specified search order
    internal func find(template: String, in source: String? = nil, on eventLoop: EventLoop) throws -> EventLoopFuture<(String, ByteBuffer)> {
        var keys: [String]
        
        switch source {
            case .none: keys = searchOrder
            case .some(let source):
                if all.contains(source) { keys = [source] }
                else { throw LeafError(.illegalAccess("Invalid source \(source) specified")) }
        }
        guard !keys.isEmpty else { throw LeafError(.illegalAccess("No searchable sources exist")) }
        
        return searchSources(t: template, on: eventLoop, s: keys)
    }
    
    private func searchSources(t: String, on eL: EventLoop, s: [String]) -> EventLoopFuture<(String, ByteBuffer)> {
        guard !s.isEmpty else { return eL.makeFailedFuture(LeafError(.noTemplateExists(t))) }
        var _more = s
        let key = _more.removeFirst()
        let source = self.lock.withLock { sources[key]! }
        let more = _more

        do {
            let file = try source.file(template: t, escape: true, on: eL)
            // Hit the file - return the combined tuple
            return eL.makeSucceededFuture(key).and(file).flatMapError { _ in
                // Or move onto the next one if this source can't get the file
                return self.searchSources(t: t, on: eL, s: more)
            }
        }
        catch {
            // If the throwing error is illegal access, fail immediately
            if let e = error as? LeafError,
               case .illegalAccess(_) = e.reason { return eL.makeFailedFuture(e) }
            else {
                // Or move onto the next one
                return searchSources(t: t, on: eL, s: more)
            }
        }
    }
}
