// MARK: Subject to change prior to 1.0.0 release
// MARK: -

extension LeafRenderer {
    /// Deprecated in Leaf-Kit 1.0.0rc-1.2
    @available(*, deprecated, message: "Use files instead of fileio")
    public var fileio: NonBlockingFileIO {
        guard let source = self.sources.sources["default"],
              let nio = source as? NIOLeafFiles else {
            fatalError("Unexpected non-NIO LeafFiles.")
        }
        return nio.fileio
    }

    /// Deprecated in Leaf-Kit 1.0.0rc-1.2
    @available(*, deprecated, message: "Use files instead of fileio")
    public convenience init(
        configuration: LeafConfiguration,
        cache: LeafCache = DefaultLeafCache(),
        fileio: NonBlockingFileIO,
        eventLoop: EventLoop
    ) {
        let sources = LeafSources()
        try! sources.register(using: NIOLeafFiles(fileio: fileio))
        
        self.init(
            configuration: configuration,
            cache: cache,
            sources: sources,
            eventLoop: eventLoop
        )
    }
}

extension LeafSource {
    /// Default implementation for non-adhering protocol implementations mimicing older LeafRenderer expansion
    /// This wrapper will be removed in a future release.
    @available(*, deprecated, message: "Update to adhere to `file(template, escape, eventLoop)`")
    func file(template: String, escape: Bool, on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        var path = template
        if path.split(separator: "/").last?.split(separator: ".").count ?? 1 < 2,
           !path.hasSuffix(".leaf") { path += ".leaf" }
        if !path.hasPrefix("/") { path = "/" + path }
        return try self.file(path: path, on: eventLoop)
    }
    
    /// Deprecated in Leaf-Kit 1.0.0rc-1.11
    /// Default implementation for newer adherants to allow older adherents to be called until upgraded
    @available(*, deprecated, message: "This default implementation should never be called")
    public func file(path: String, on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        fatalError("This default implementation should never be called")
    }
}

/// Deprecated in Leaf-Kit 1.0.0rc-1.11
@available(*, deprecated, renamed: "LeafSource")
typealias LeafFiles = LeafSource
