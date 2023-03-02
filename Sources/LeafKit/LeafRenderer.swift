import NIO

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
    public let tags: [String: LeafTag]
    /// A thread-safe implementation of `LeafCache` protocol
    public let cache: LeafCache
    /// A thread-safe implementation of `LeafSource` protocol
    public let sources: LeafSources
    /// The NIO `EventLoop` on which this instance of `LeafRenderer` will operate
    public let eventLoop: EventLoop
    /// Any custom instance data to use (eg, in Vapor, the `Application` and/or `Request` data)
    public let userInfo: [AnyHashable: Any]
    
    /// Initial configuration of LeafRenderer.
    public init(
        configuration: LeafConfiguration,
        tags: [String: LeafTag] = defaultTags,
        cache: LeafCache = DefaultLeafCache(),
        sources: LeafSources,
        eventLoop: EventLoop,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.configuration = configuration
        self.tags = tags
        self.cache = cache
        self.sources = sources
        self.eventLoop = eventLoop
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
    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        guard path.count > 0 else { return self.eventLoop.makeFailedFuture(LeafError(.noTemplateExists("(no key provided)"))) }

        return render(source: nil, path: path, context: context)
    }

    /// load an unsubstituted ast from the given source at the given path
    internal func findUnsubstituted(source: String?, path: String) -> EventLoopFuture<[Statement]> {
        do {
            return try sources.find(template: path, in: source, on: self.eventLoop)
                .flatMap { (data: (String, ByteBuffer)) -> EventLoopFuture<[Statement]> in
                    var (_, buffer) = data
                    let scanner = LeafScanner(name: path, source: buffer.readString(length: buffer.readableBytes) ?? "<err>")
                    let parser = LeafParser(from: scanner)
                    do {
                        let ast = try parser.parse()
                        return self.eventLoop.makeSucceededFuture(ast)
                    } catch { return self.eventLoop.makeFailedFuture(error) }
                }
        } catch { return self.eventLoop.makeFailedFuture(error) }
    }

    /// load and substitute the given template in the given ast
    internal func loadSubstitute(
        source: String?,
        unsubstituted path: String,
        context: [String: LeafData],
        in combined: [Statement],
        reduceStack: [String]
    ) -> EventLoopFuture<[Statement]> {
        return findUnsubstituted(source: source, path: path)
            .flatMap { ast in self.reducePass(source: source, context: context, ast: ast, reduceStack: reduceStack)}
            .flatMap { (fragment: [Statement]) -> EventLoopFuture<[Statement]> in
                let newAst = combined.substituteExtend(name: path, with: { exports in
                    var frag = fragment
                    for export in exports {
                        frag = frag.substituteImport(name: String(export.name), with: .init(combined: export.body))
                    }
                    return .init(combined: frag)
                })
                return self.eventLoop.makeSucceededFuture(newAst)
            }
    }

    /// do a pass of reducing an ast
    internal func reducePass(source: String?, context: [String: LeafData], ast: [Statement], reduceStack: [String]) -> EventLoopFuture<[Statement]> {
        var val: EventLoopFuture<[Statement]>?
        for item in ast.unsubstitutedExtends() {
            guard !reduceStack.contains(item) else {
                return self.eventLoop.makeFailedFuture(LeafError(.cyclicalReference(item, reduceStack)))
            }
            if let futureVal = val {
                val = futureVal.flatMap { self.loadSubstitute(source: source, unsubstituted: item, context: context, in: $0, reduceStack: reduceStack + [item]) }
            } else {
                val = self.loadSubstitute(source: source, unsubstituted: item, context: context, in: ast, reduceStack: reduceStack + [item])
            }
        }

        // reduce it...
        guard let reduced = val else {
            // or just return it verbatim, if there's nothing unsubstituted to flatten
            return self.eventLoop.makeSucceededFuture(ast)
        }
        return reduced.flatMap { ast in self.reducePass(source: source, context: context, ast: ast, reduceStack: reduceStack) }
    }

    /// find and substitute an AST
    internal func findAndSubstitute(source: String?, path: String, context: [String: LeafData]) -> EventLoopFuture<[Statement]> {
            // read the raw ast...
        return findUnsubstituted(source: source, path: path)
            // flatten it
            .flatMap { (ast: [Statement]) -> EventLoopFuture<[Statement]> in
                return self.reducePass(source: source, context: context, ast: ast, reduceStack: [])
            }
            // if we got here, time to cache it
            .flatMap { (ast: [Statement]) -> EventLoopFuture<[Statement]> in
                return self.cache.insert(LeafAST(name: path, ast: ast), on: self.eventLoop, replace: true)
                    .flatMap { _ in self.eventLoop.makeSucceededFuture(ast) }
            }
    }

    /// render a template at the given path loaded from the given source
    internal func render(source: String?, path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        // do we already have a substituted AST?
        return self.cache.retrieve(documentName: path, on: self.eventLoop)
            .flatMap { ast -> EventLoopFuture<[Statement]> in
                if let done = ast {
                    // if so, let's just work with that...
                    return self.eventLoop.makeSucceededFuture(done.ast)
                }
                // otherwise we find one and substitute it
                return self.findAndSubstitute(source: source, path: path, context: context)
            }
            // and then finally render
            .flatMap { (ast: [Statement]) -> EventLoopFuture<ByteBuffer> in
                var serializer = LeafSerializer(ast: ast, tags: self.tags, userInfo: self.userInfo, ignoreUnfoundImports: self.configuration._ignoreUnfoundImports)
                do {
                    return self.eventLoop.makeSucceededFuture(try serializer.serialize(context: context))
                } catch { return self.eventLoop.makeFailedFuture(error) }
            }
    }
}
