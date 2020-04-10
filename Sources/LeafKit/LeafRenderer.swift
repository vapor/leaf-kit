import NIOConcurrencyHelpers
import Foundation

public enum LeafError: LocalizedError {
    case unknownError(String)
    case unsupportedFeature(String)
    case cachingDisabled
    case keyExists(String)
    case noValueForKey(String)
    case unresolvedAST(String)
    case noTemplateExists(String)
    case cyclicalReference(String)

    var errorDescription: String {
        switch self {
            case .unknownError(let message): return message
            case .unsupportedFeature(let feature): return "\(feature) is not implemented"
            case .cachingDisabled: return "Caching is globablly disabled"
            case .keyExists(let key): return "Existing entry \(key): use insert with replace=true to overrride"
            case .noValueForKey(let key): return "No cache entry exists for \(key)"
            case .unresolvedAST(let key): return "Flat AST expected; \(key) has unresolved dependencies"
            case .noTemplateExists(let key): return "No template found named \(key)"
            case .cyclicalReference(let key): return "\(key) was referenced causing a cyclical loop"
        }
    }

    init(_ message: String) {
        self = .unknownError(message)
    }
}

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
]

public struct LeafConfiguration {
    public var rootDirectory: String

    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }
}

public protocol LeafCache {
    func insert(
        _ document: LeafAST,
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST>
    func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST?>
    var isEnabled : Bool { get set }
}

public final class DefaultLeafCache: LeafCache {
    let lock: Lock
    var cache: [String: LeafAST]
    public var isEnabled: Bool = true

    public init() {
        self.lock = .init()
        self.cache = [:]
    }

    public func insert(
        _ document: LeafAST,
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST> {
        self.lock.lock()
        defer { self.lock.unlock() }
        if isEnabled {
            self.cache[document.name] = document
        }
        return loop.makeSucceededFuture(document)
    }

    public func load(
        documentName: String,
        on loop: EventLoop
    ) -> EventLoopFuture<LeafAST?> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return loop.makeSucceededFuture(self.cache[documentName])
    }
}

public struct LeafContext {
    public let parameters: [LeafData]
    public let data: [String: LeafData]
    public let body: [Syntax]?
    public let userInfo: [AnyHashable: Any]

    init(
        parameters: [LeafData],
        data: [String: LeafData],
        body: [Syntax]?,
        userInfo: [AnyHashable: Any]
    ) throws {
        self.parameters = parameters
        self.data = data
        self.body = body
        self.userInfo = userInfo
    }

    /// Throws an error if the parameter count does not equal the supplied number `n`.
    public func requireParameterCount(_ n: Int) throws {
        guard parameters.count == n else {
            throw "Invalid parameter count: \(parameters.count)/\(n)"
        }
    }

    /// Throws an error if this tag does not include a body.
    public func requireBody() throws -> [Syntax] {
        guard let body = body else {
            throw "Missing body"
        }

        return body
    }

    /// Throws an error if this tag includes a body.
    public func requireNoBody() throws {
        guard body == nil else {
            throw "Extraneous body"
        }
    }
}

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to lowercase unexpected data"
        }
        return .init(.string(str.lowercased()))
    }
}

public protocol LeafFiles {
    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer>
}

public struct NIOLeafFiles: LeafFiles {
    let fileio: NonBlockingFileIO

    public init(fileio: NonBlockingFileIO) {
        self.fileio = fileio
    }

    public func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        let openFile = self.fileio.openFile(path: path, eventLoop: eventLoop)
        return openFile.flatMapErrorThrowing { error in
            throw "unable to open file \(path)"
        }.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
            let allocator = ByteBufferAllocator()
            let read = self.fileio.read(fileRegion: region, allocator: allocator, eventLoop: eventLoop)
            return read.flatMapThrowing { (buffer)  in
                try handle.close()
                return buffer
            }
        }
    }
}

public final class LeafRenderer {
    public let configuration: LeafConfiguration
    public let tags: [String: LeafTag]
    public let cache: LeafCache
    public let files: LeafFiles
    public let eventLoop: EventLoop
    public let userInfo: [AnyHashable: Any]

    public init(
        configuration: LeafConfiguration,
        tags: [String: LeafTag] = defaultTags,
        cache: LeafCache = DefaultLeafCache(),
        files: LeafFiles,
        eventLoop: EventLoop,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.configuration = configuration
        self.tags = tags
        self.cache = cache
        self.files = files
        self.eventLoop = eventLoop
        self.userInfo = userInfo
    }

    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        let document = fetchFlat(template: path)
        return document.flatMapThrowing { try self.render($0, context: context) }
    }

    func render(_ doc: LeafAST, context: [String: LeafData]) throws -> ByteBuffer {
        guard doc.flat == true else { throw LeafError.unresolvedAST(doc.name) }

        var serializer = LeafSerializer(
            ast: doc.ast,
            context: context,
            tags: self.tags,
            userInfo: self.userInfo
        )
        return try serializer.serialize()
    }

    private func expand(template: String) -> String {
        var path = template
        // ignore files that already have a type
        if path.split(separator: ".").count < 2, !path.hasSuffix(".leaf") {
            path += ".leaf"
        }

        if !path.hasPrefix("/") {
            path = self.configuration.rootDirectory.trailSlash + path
        }
        return path
    }

    private func fetchFlat(template: String) -> EventLoopFuture<LeafAST> {
        return self.fetch(template: template).flatMapThrowing { ast in
            guard let ast = ast else { throw LeafError.noTemplateExists(template) }
            guard ast.flat else { throw LeafError.unresolvedAST(template) }
            return ast
        }
    }

    private func fetch(template: String, chain: Set<String> = .init()) -> EventLoopFuture<LeafAST?> {
        return cache.load(documentName: template, on: eventLoop).flatMap { cached in
            guard let cached = cached else {
                return self.read(name: template).flatMap { ast in
                    guard let ast = ast else { return self.eventLoop.makeSucceededFuture(nil) }
                    return self.resolve(ast: ast, chain: chain, forceCaching: true).map {$0}
                }
            }
            guard cached.flat == false else { return self.eventLoop.makeSucceededFuture(cached) }
            return self.resolve(ast: cached, chain: chain).map {$0}
        }
    }

    // resolve is only guaranteed to try to resolve an AST to flatness, not to succeed
    private func resolve(ast: LeafAST, chain: Set<String>, forceCaching: Bool = false) -> EventLoopFuture<LeafAST> {
        guard ast.flat == false || forceCaching == true else { return self.eventLoop.makeSucceededFuture(ast) }

        var chain = chain
        _ = chain.insert(ast.name)
        guard chain.intersection(ast.unresolvedRefs).count == 0 else {
            return self.eventLoop.makeFailedFuture(LeafError.cyclicalReference(ast.name))
        }

        let fetchRequests = ast.unresolvedRefs.map { self.fetch(template: $0, chain: chain) }
        let results = EventLoopFuture.whenAllComplete(fetchRequests, on: self.eventLoop)
 
        return results.flatMapThrowing { results -> LeafAST in
            let results = results
            var externals: [String: LeafAST] = [:]
            for result in results {
                // skip any unresolvable references
                guard let external = try result.get() else { continue }
                externals[external.name] = external
            }
            // return new inlined AST that may potentially still have references that can't be resolved
            return LeafAST(from: ast, referencing: externals)
        }.flatMap { resolved in
            guard forceCaching else { return self.eventLoop.makeSucceededFuture(resolved) }
            return self.cache.insert(resolved, on: self.eventLoop)
        }
    }

    private func read(name: String) -> EventLoopFuture<LeafAST?> {
        let path = expand(template: name)
        let raw = readBytes(file: path)

        return raw.flatMapThrowing { raw -> LeafAST? in
            var raw = raw

            // MARK: Should this actually throw an error if readString can't read readableBytes?
            let template = raw.readString(length: raw.readableBytes) ?? ""
            var lexer = LeafLexer(name: name, template: template)
            let tokens = try lexer.lex()
            var parser = LeafParser(name: name, tokens: tokens)
            let ast = try parser.parse()
            return LeafAST(name: name, ast: ast)
        }
    }

//    private func readDependencies... *obviated by new fetchFlat/fetch functions*

    private func readBytes(file: String) -> EventLoopFuture<ByteBuffer> {
        self.files.file(path: file, on: self.eventLoop)
    }
}

extension Array where Element == Syntax {
    var dependencies: [String] {
        return extensions.map { $0.key }
    }

    private var extensions: [Syntax.Extend] {
        return compactMap {
            switch $0 {
            case .extend(let e): return e
            default: return nil
            }
        }
    }
}

extension String {
    internal var trailSlash: String {
        if hasSuffix("/") { return self }
        else { return self + "/" }
    }
}
