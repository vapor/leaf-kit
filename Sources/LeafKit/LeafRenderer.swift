public struct LeafConfig {
    public var rootDirectory: String
    
    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }
}

protocol LeafCache {
    func insert(_ document: ResolvedDocument, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument>
    func load(path: String, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument?>
}

final class Cache: LeafCache {
    func insert(_ document: ResolvedDocument, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument> {
        return loop.makeSucceededFuture(document)
    }
    
    func load(path: String, on loop: EventLoop) -> EventLoopFuture<ResolvedDocument?> {
        return loop.makeSucceededFuture(nil)
    }
}

public struct LeafContext {
    let params: [ParameterDeclaration]
    let data: [String: LeafData]
    let body: [Syntax]?
}

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        let resolver = ParameterResolver(params: ctx.params, data: ctx.data)
        let resolved = try resolver.resolve()
        guard let str = resolved.first?.result.string else { throw "unable to lowercase unexpected data" }
        return .init(.string(str.lowercased()))
    }
}

public final class LeafRenderer {
    let config: LeafConfig
    let file: NonBlockingFileIO
    public let eventLoop: EventLoop
    
    // TODO: More Cache Options
    let cache: LeafCache = Cache()
    
    public init(
        config: LeafConfig,
        threadPool: NIOThreadPool,
        eventLoop: EventLoop
    ) {
        self.config = config
        self.file = .init(threadPool: threadPool)
        self.eventLoop = eventLoop
    }
    
    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        let expanded = expand(path: path)
        let document = fetch(path: expanded)
        return document.flatMapThrowing { try self.render($0, context: context) }
    }
    
    func render(_ doc: ResolvedDocument, context: [String: LeafData]) throws -> ByteBuffer {
        var serializer = LeafSerializer(ast: doc.ast, context: context)
        return try serializer.serialize()
    }
    
    private func expand(path: String) -> String {
        var path = path
        // ignore files that already have a type
        if path.split(separator: ".").count < 2, !path.hasSuffix(".leaf") {
            path += ".leaf"
        }
        
        if !path.hasPrefix("/") {
            path = config.rootDirectory.trailSlash + path
        }
        return path
    }
    
    private func fetch(path: String) -> EventLoopFuture<ResolvedDocument> {
        let expanded = expand(path: path)
        return cache.load(path: expanded, on: eventLoop).flatMap { cached in
            guard let cached = cached else { return self.read(file: expanded) }
            return self.eventLoop.makeSucceededFuture(cached)
        }
    }
    
    private func read(file: String) -> EventLoopFuture<ResolvedDocument> {
        print("reading \(file)")
        let raw = readBytes(file: file)
        
        let syntax = raw.flatMapThrowing { raw -> [Syntax] in
            var raw = raw
            guard let template = raw.readString(length: raw.readableBytes) else { return [] }
            var lexer = LeafLexer(name: file, template: template)
            let tokens = try lexer.lex()
            var parser = LeafParser(name: file, tokens: tokens)
            return try parser.parse()
        }
        
        return syntax.flatMap { syntax in
            let dependencies = self.readDependencies(syntax.dependencies)
            let resolved = dependencies.flatMapThrowing { dependencies -> ResolvedDocument in
                let unresolved = UnresolvedDocument(name: file, raw: syntax)
                let resolver = ExtendResolver(document: unresolved, dependencies: dependencies)
                return try resolver.resolve(rootDirectory: self.config.rootDirectory)
            }
            
            return resolved.flatMap { resolved in self.cache.insert(resolved, on: self.eventLoop) }
        }
    }
    
    private func readDependencies(_ dependencies: [String]) -> EventLoopFuture<[ResolvedDocument]> {
        let fetchRequests = dependencies.map(self.fetch)
        let results = EventLoopFuture.whenAllComplete(fetchRequests, on: self.eventLoop)
        return results.flatMapThrowing { results in
            return try results.map { result -> ResolvedDocument in
                switch result {
                case .success(let ob): return ob
                case .failure(let e): throw e
                }
            }
        }
    }
    
    private func readBytes(file: String) -> EventLoopFuture<ByteBuffer> {
        let openFile = self.file.openFile(path: file, eventLoop: self.eventLoop)
        return openFile.flatMapErrorThrowing { error in
            throw "unable to open file \(file)"
        }.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
            let allocator = ByteBufferAllocator()
            let read = self.file.read(fileRegion: region, allocator: allocator, eventLoop: self.eventLoop)
            return read.flatMapThrowing { (buffer)  in
                try handle.close()
                return buffer
            }
        }
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
