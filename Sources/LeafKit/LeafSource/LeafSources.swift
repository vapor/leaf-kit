import NIOConcurrencyHelpers
import NIOCore

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
public actor LeafSources: Sendable {
    // MARK: - Public

    /// All available `LeafSource`s of templates
    public var all: Set<String> {
        .init(self.sources.keys)
    }
    /// Configured default implicit search order of `LeafSource`'s
    public var searchOrder: [String] {
        self.order
    }

    public init() {
        self.sources = [:]
        self.order = []
    }

    /// Convenience for initializing a `LeafSources` object with a single `LeafSource`
    /// - Parameter source: A fully configured `LeafSource`
    /// - Returns: Configured `LeafSource` instance
    init(singleSource: any LeafSource) {
        self.sources = ["default": singleSource]
        self.order = ["default"]
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
        guard !self.sources.keys.contains(key) else {
            throw LeafError.unknownError("Can't replace source at \(key)")
        }
        self.sources[key] = source
        if searchable {
            self.order.append(key)
        }
    }

    // MARK: - Internal Only

    // Note: nonisolated(unsafe) is safe because these are protected by the lock
    private(set) var sources: [String: any LeafSource]
    private var order: [String]

    /// Locate a template from the sources; if a specific source is named, only try to read from it. Otherwise, use the specified search order
    func find(template: String, in source: String? = nil) async throws -> (String, ByteBuffer) {
        var keys: [String]

        switch source {
        case .none:
            keys = self.searchOrder
        case .some(let source):
            if all.contains(source) {
                keys = [source]
            } else {
                throw LeafError.illegalAccess("Invalid source \(source) specified")
            }
        }
        guard !keys.isEmpty else {
            throw LeafError.illegalAccess("No searchable sources exist")
        }

        return try await self.searchSources(template: template, sources: keys)
    }

    private func searchSources(template: String, sources: [String]) async throws -> (String, ByteBuffer) {
        guard !sources.isEmpty else {
            throw LeafError.noTemplateExists(at: template)
        }

        var remaining = sources
        let key = remaining.removeFirst()
        let source = self.sources[key]!

        do {
            // Assuming source.file has been updated to be async
            let file = try await source.file(template: template, escape: true)
            return (key, file)
        } catch let error as LeafError where error.errorType == .illegalAccess {
            // If the thrown error is illegal access, fail immediately
            throw error
        } catch {
            // Try the next source
            return try await searchSources(template: template, sources: remaining)
        }
    }
}
