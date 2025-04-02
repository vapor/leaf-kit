import NIOCore

/// Public protocol to adhere to in order to provide template source originators to `LeafRenderer`
public protocol LeafSource: Sendable {
    /// Given a path name, return an EventLoopFuture holding a ByteBuffer
    /// - Parameters:
    ///   - template: Relative template name (eg: `"path/to/template"`)
    ///   - escape: If the adherent represents a filesystem or something scoped that enforces
    ///             a concept of directories and sandboxing, whether to allow escaping the view directory
    /// - Returns: A `ByteBuffer` with the raw template
    func file(template: String, escape: Bool) async throws -> ByteBuffer
}
