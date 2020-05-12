/// Default implementation of `LeafFiles` adhering object that provides a non-blocking file reader
/// to `LeafRenderer`
public struct NIOLeafFiles: LeafFiles {
    let fileio: NonBlockingFileIO

    public init(fileio: NonBlockingFileIO) {
        self.fileio = fileio
    }

    public func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        let openFile = self.fileio.openFile(path: path, eventLoop: eventLoop)
        return openFile.flatMapErrorThrowing { error in
            throw LeafError(.noTemplateExists(path))
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
