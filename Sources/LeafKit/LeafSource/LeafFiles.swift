// FIXME: `LeafFiles` to be generalized as `LeafSource`
/// Template sources should be generalized to allow database backends for sourcing templates

/// Public protocol to adhere to in order to provide template source originators to `LeafRenderer`
public protocol LeafFiles {
    /// Given a path name, return an EventLoopFuture holding a ByteBuffer
    /// - Parameters:
    ///   - path: Fully expanded pathname to file for reading
    ///   - eventLoop: `EventLoop` on which to perform file access
    func file(path: String, on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer>
}
