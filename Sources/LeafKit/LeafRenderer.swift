import NIOCore

// MARK: - `LeafRenderer` Summary

/// `LeafRenderer` implements the full Leaf language pipeline.
///
/// It must be configured before use with the appropriate `LeafConfiguration` and consituent
/// threadsafe protocol-implementating modules (an NIO `EventLoop`, `LeafCache`, `LeafSource`,
/// and potentially any number of custom `LeafTag` additions to the language).
///
/// Additional instances of LeafRenderer can then be created using these shared modules to allow
/// concurrent rendering, potentially with unique per-instance scoped data via `userInfo`.
public final class LeafRenderer {
    // MARK: - Public Only

    /// An initialized `LeafConfiguration` specificying default directory and tagIndicator
    public let configuration: LeafConfiguration
    /// A keyed dictionary of custom `LeafTags` to extend Leaf's basic functionality, registered
    /// with the names which will call them when rendering - eg `tags["tagName"]` can be used
    /// in a template as `#tagName(parameters)`
    public let tags: [String: any LeafTag]
    /// A thread-safe implementation of `LeafCache` protocol
    public let cache: any LeafCache
    /// A thread-safe implementation of `LeafSource` protocol
    public let sources: LeafSources
    /// Any custom instance data to use (eg, in Vapor, the `Application` and/or `Request` data)
    public let userInfo: [AnyHashable: Any]

    /// Initial configuration of LeafRenderer.
    public init(
        configuration: LeafConfiguration,
        tags: [String: any LeafTag] = defaultTags,
        cache: any LeafCache = DefaultLeafCache(),
        sources: LeafSources,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.configuration = configuration
        self.tags = tags
        self.cache = cache
        self.sources = sources
        self.userInfo = userInfo
    }

    /// The public interface to `LeafRenderer`
    /// - Parameter path: Name of the template to be used
    /// - Parameter context: Any unique context data for the template to use
    /// - Returns: Serialized result of using the template, or a failed future
    ///
    /// Interpretation of `path` is dependent on the implementation of `LeafSource` but is assumed to
    /// be relative to `LeafConfiguration.rootDirectory`.
    ///
    /// Where `LeafSource` is a file sytem based source, some assumptions should be made; `.leaf`
    /// extension should be inferred if none is provided- `"path/to/template"` corresponds to
    /// `"/.../ViewDirectory/path/to/template.leaf"`, while an explicit extension -
    /// `"file.svg"` would correspond to `"/.../ViewDirectory/file.svg"`
    public func render(path: String, context: [String: LeafData]) async throws -> ByteBuffer {
        guard !path.isEmpty else {
            throw LeafError(.noTemplateExists("(no key provided)"))
        }

        // If a flat AST is cached and available, serialize and return
        if let flatAST = try await self.getFlatCachedHit(path),
            let buffer = try? self.serialize(flatAST, context: context)
        {
            return buffer
        }

        // Otherwise operate using normal future-based full resolving behavior
        let cached = try await self.cache.retrieve(documentName: path)
        do {
            guard let cached else {
                throw LeafError(.noValueForKey(path))
            }
            guard cached.flat else {
                throw LeafError(.unresolvedAST(path, Array(cached.unresolvedRefs)))
            }
            return try self.serialize(cached, context: context)
        } catch {
            let ast = try await self.fetch(template: path)
            guard let ast else {
                throw LeafError(.noTemplateExists(path))
            }
            guard ast.flat else {
                throw LeafError(.unresolvedAST(path, Array(ast.unresolvedRefs)))
            }
            return try self.serialize(ast, context: context)
        }
    }

    // MARK: - Private Only

    /// Given a `LeafAST` and context data, serialize the AST with provided data into a final render
    private func serialize(_ doc: LeafAST, context: [String: LeafData]) throws -> ByteBuffer {
        guard doc.flat else {
            throw LeafError(.unresolvedAST(doc.name, Array(doc.unresolvedRefs)))
        }

        var serializer = LeafSerializer(
            ast: doc.ast,
            tags: self.tags,
            userInfo: self.userInfo,
            ignoreUnfoundImports: self.configuration._ignoreUnfoundImports
        )
        return try serializer.serialize(context: context)
    }

    // MARK: `expand()` obviated

    /// Get a `LeafAST` from the configured `LeafCache` or read the raw template if none is cached
    ///
    /// - If the AST can't be found (either from cache or reading) return nil
    /// - If found or read and flat, return complete AST.
    /// - If found or read and non-flat, attempt to resolve recursively via `resolve()`
    ///
    /// Recursive calls to `fetch()` from `resolve()` must provide the chain of extended
    /// templates to prevent cyclical errors
    private func fetch(template: String, chain: [String] = []) async throws -> LeafAST? {
        let cached = try await self.cache.retrieve(documentName: template)
        guard let cached else {
            let ast = try await self.read(name: template, escape: true)
            guard let ast else {
                return nil
            }
            return try await self.resolve(ast: ast, chain: chain)
        }
        guard !cached.flat else {
            return cached
        }
        return try await self.resolve(ast: cached, chain: chain)
    }

    /// Attempt to resolve a `LeafAST`
    ///
    /// - If flat, cache and return
    /// - If there are extensions, ensure that (if we've been called from a chain of extensions) no cyclical
    ///   references to a previously extended template would occur as a result
    /// - Recursively `fetch()` any extended template references and build a new `LeafAST`
    private func resolve(ast: LeafAST, chain: [String]) async throws -> LeafAST {
        // if the ast is already flat, cache it immediately and return
        guard !ast.flat else {
            return try await self.cache.insert(ast, replace: true)
        }

        var chain = chain
        chain.append(ast.name)

        let intersect = ast.unresolvedRefs.intersection(Set<String>(chain))
        guard intersect.count == 0 else {
            let badRef = intersect.first ?? ""
            chain.append(badRef)
            throw LeafError(.cyclicalReference(badRef, chain))
        }

        var results: [LeafAST?] = []
        for ref in ast.unresolvedRefs {
            results.append(try await self.fetch(template: ref, chain: chain))
        }

        var externals: [String: LeafAST] = [:]

        for result in results {
            // skip any unresolvable references
            guard let result else {
                continue
            }
            externals[result.name] = result
        }
        // create new AST with loaded references
        let new = LeafAST(from: ast, referencing: externals)
        // Check new AST's unresolved refs to see if extension introduced new refs
        if !new.unresolvedRefs.subtracting(ast.unresolvedRefs).isEmpty {
            // AST has new references - try to resolve again recursively
            return try await self.resolve(ast: new, chain: chain)
        } else {
            // Cache extended AST & return - AST is either flat or unresolvable
            return try await self.cache.insert(new, replace: true)
        }
    }

    /// Read in an individual `LeafAST`
    ///
    /// If the configured `LeafSource` can't read a file, future will fail - otherwise, a complete (but not
    /// necessarily flat) `LeafAST` will be returned.
    private func read(name: String, escape: Bool = false) async throws -> LeafAST? {
        var raw = try await self.sources.find(template: name, in: nil)

        guard let template = raw.1.readString(length: raw.1.readableBytes) else {
            throw LeafError.init(.unknownError("File read failed"))
        }
        var lexer = LeafLexer(name: name, template: LeafRawTemplate(name: name, src: template))
        let tokens = try lexer.lex()
        var parser = LeafParser(name: name, tokens: tokens)
        let ast = try parser.parse()
        return LeafAST(name: name, ast: ast)
    }

    private func getFlatCachedHit(_ path: String) async throws -> LeafAST? {
        // If cache provides blocking load, try to get a flat AST immediately
        guard
            let cached = try? await self.cache.retrieve(documentName: path),
            cached.flat
        else {
            return nil
        }
        return cached
    }
}
