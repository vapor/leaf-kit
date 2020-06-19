/// Public protocol to adhere to in order to provide template source originators to `LeafRenderer`
public protocol LeafSource {
    /// Given a path name, return an EventLoopFuture holding a ByteBuffer
    /// - Parameters:
    ///   - path: Fully expanded pathname to file for reading
    ///   - escape: Whether to allow escaping paths up to `sandbox` level at most
    ///   - eventLoop: `EventLoop` on which to perform file access
    func file(template: String,
              escape: Bool,
              on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer>
    
    /// DO NOT IMPLEMENT. Deprecated as of Leaf-Kit 1.0.0rc1.??
    @available(*, deprecated, message: "Update to adhere to `file(template, escape, eventLoop)`")
    func file(path: String, on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer>
}
