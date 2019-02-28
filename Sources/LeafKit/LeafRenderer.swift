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

public final class LeafRenderer {
    let config: LeafConfig
    let file: NonBlockingFileIO
    let eventLoop: EventLoop
    
    // TODO: More Cache Options
    let cache: LeafCache = Cache()
    
    public init(
        config: LeafConfig,
        threadPool: BlockingIOThreadPool,
        eventLoop: EventLoop
    ) {
        self.config = config
        self.file = .init(threadPool: threadPool)
        self.eventLoop = eventLoop
    }
    
    public func render(path: String, context: [String: LeafData]) -> EventLoopFuture<ByteBuffer> {
        let path = path.hasSuffix(".leaf") ? path : path + ".leaf"
        let expanded = config.rootDirectory + path
        let document = fetch(path: expanded)
        return document.flatMapThrowing { document in
            throw "todo: serialize document w/ context"
        }
    }
    
    private func fetch(path: String) -> EventLoopFuture<ResolvedDocument> {
        let path = path.hasSuffix(".leaf") ? path : path + ".leaf"
        let expanded = config.rootDirectory + path
        return cache.load(path: expanded, on: eventLoop).flatMap { cached in
            guard let cached = cached else { return self.read(file: path) }
            return self.eventLoop.makeSucceededFuture(cached)
        }
    }
    
    private func read(file: String) -> EventLoopFuture<ResolvedDocument> {
        let raw = readBytes(file: file)
        
        let syntax = raw.flatMapThrowing { raw -> [Syntax] in
            var lexer = LeafLexer(template: raw)
            let tokens = try lexer.lex()
            var parser = LeafParser(tokens: tokens)
            return try parser.parse()
        }
        
        return syntax.flatMap { syntax in
            let dependencies = self.readDependencies(syntax.dependencies)
            let resolved = dependencies.flatMapThrowing { dependencies -> ResolvedDocument in
                let unresolved = UnresolvedDocument(name: file, raw: syntax)
                let resolver = ExtendResolver(document: unresolved, dependencies: dependencies)
                return try resolver.resolve()
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
        let openFile  = self.file.openFile(path: file, eventLoop: self.eventLoop)
        return openFile.flatMap { (handle, region) -> EventLoopFuture<ByteBuffer> in
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
