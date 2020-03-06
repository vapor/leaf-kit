extension LeafRenderer {
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
