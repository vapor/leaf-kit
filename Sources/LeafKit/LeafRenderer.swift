public struct LeafConfig {
    public var rootDirectory: String
    
    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }
}

public final class LeafRenderer {
    let config: LeafConfig
    let file: NonBlockingFileIO
    let eventLoop: EventLoop
    
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
        return self.file.openFile(path: config.rootDirectory + path, eventLoop: self.eventLoop).flatMap { res in
            return self.file.read(
                fileRegion: res.1, allocator: ByteBufferAllocator(),
                eventLoop: self.eventLoop
            ).flatMapThrowing { buffer in
                try res.0.close()
                return buffer
            }
        }.flatMapThrowing { template in
            return try self.render(template: template, context: context)
        }
    }
    
    public func render(template: ByteBuffer, context: [String: LeafData]) throws -> ByteBuffer {
        var lexer = LeafLexer(template: template)
        let tokens = try lexer.lex()
        var parser = LeafParser(tokens: tokens)
        let raw = try parser.parse()
        
        #warning("TODO: resolve import / extend / static embed")
        throw "todo: serialize"
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
