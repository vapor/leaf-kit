extension LeafRenderer {
    /// Deprecated in Leaf-Kit 1.0.0rc-1.2
    @available(*, deprecated, message: "Use files instead of fileio")
    public var fileio: NonBlockingFileIO {
        guard let nio = self.files as? NIOLeafFiles else {
            fatalError("Unexpected non-NIO leaf files.")
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
        self.init(
            configuration: configuration,
            cache: cache,
            files: NIOLeafFiles(fileio: fileio),
            eventLoop: eventLoop
        )
    }
}
