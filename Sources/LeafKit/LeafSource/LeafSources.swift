// MARK: Subject to change prior to 1.0.0 release
// MARK: -


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
public final class LeafSources {
    // MARK: - Public
    
    /// All available `LeafSource`s of templates
    public var all: Set<String> { lock.withLock { .init(sources.keys) } }
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
        if sources.keys.contains(key) { throw "Can't replace source at \(key)" }
        lock.withLock {
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
    
    // MARK: - Internal/Private Only
    internal private(set) var sources: [String: LeafSource]
    private var order: [String]
    private let lock: Lock = .init()
    
    /// Locate a template from the sources; if a specific source is named, only try to read from it.
    /// Otherwise, use the specified search order. Key (and thus AST name) are "$:template" when no source
    /// was specified, or "source:template" when specified
    internal func find(_ template: String,
                       in source: String? = nil,
                       on eL: EventLoop) -> EventLoopFuture<(key: String,
                                                             buffer: ByteBuffer)> {
        let sourced = source == nil
        let sources = sourced ? searchOrder
                              : all.contains(source!) ? [source!] : []
        if sources.isEmpty {
            let e = sourced ? "No searchable sources exist"
                            : "Invalid source \(source!) specified"
            return fail(.illegalAccess(e), on: eL)
        }
        return searchSources(template, sources, on: eL).map {
                    ((sourced ? "$" : source!) + ":\(template)", $0.buffer) }
    }
    
    
    private func searchSources(_ t: String,
                               _ s: [String],
                               on eL: EventLoop) -> EventLoopFuture<(source: String,
                                                                     buffer: ByteBuffer)> {
        if s.isEmpty { return fail(.noTemplateExists(t), on: eL) }
        
        var rest = s
        let key = rest.removeFirst()
        lock.lock()
        let source = sources[key]!
        lock.unlock()
        
        return source.file(template: t, escape: true, on: eL)
                     .map { (source: key, buffer: $0) }
                     .flatMapError { if let e = $0 as? LeafError,
                                        case .illegalAccess = e.reason {
                                            return fail(e, on: eL) }
                                     return self.searchSources(t, rest, on: eL) }
                     
    }
}
