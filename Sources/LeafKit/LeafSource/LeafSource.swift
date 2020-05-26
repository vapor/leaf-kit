/// Temporary compatibility for previous versions
public typealias LeafFiles = LeafSource

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
}

/// Default implementation for non-adhering protocol adopters of older versions
extension LeafSource {
    public func file(template: String,
              escape: Bool,
              on eventLoop: EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        return eventLoop.makeFailedFuture(
            LeafError(.unsupportedFeature("Upgrade protocol adopter for sandboxing"))
        )
    }
}
