
@available(*, deprecated, message: "Access to Syntax is removed")
public indirect enum Syntax {}

/// `LeafTag` is entirely deprecated.
///
/// See `LeafFunction/Method/Block` for replacement conformances, and register with
/// `LeafConfiguration.entities` rather than with `LeafRenderer.defaultTags`
@available(*, deprecated, message: "Adhere to LeafFunction/Method/Block as appropriate")
public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

/// `LeafContext` is entirely deprecated as a value passing object to the replacement to `LeafTag`.
///
///     LeafFunction or LeafMethod:
///         evaluate(_ params: LeafCallValues)
///     LeafBlock:
///        evaluateScope(_ params: LeafCallValues,
///                      _ variables: inout [String: LeafData])
///       reEvaluateScope(_ variables: inout [String: LeafData])
/// -                           -                               -
///     parameters: [LeafData] /*replaced by*/ LeafCallValues
/// `LeafCallValues` is an opaque container of `LeafData` that allows guarded, bounded access to
/// exact matches by index and (optional) label for values matching adherent's call signature
///
///     data: [String: LeafData] /* replaced by */ inout [String: LeafData]
/// `LeafBlock` adherents are provided an inout dictionary to write the specific scope variables they are
/// setting for underlying scopes.
///
///     body: [Syntax]? /* removed entirely */
/// `LeafBlock` adherents may no longer read their body syntax at all. Future release will introduce a
/// `LeafRawBlock` protocol that may receive the serialized results of its contained body *after* processing.
///
///     userInfo: [AnyHashable: Any] /* removed entirely */
/// Leaf templates now have access to additional information in the form of scoped variables
/// (eg: `$server.name` for a previously registered "server" variable scope)
@available(*, deprecated, message: "Adhere to LeafFunction/Method/Block/UnsafeEntity as appropriate")
public struct LeafContext {
    public let parameters: [LeafData]
    public let data: [String: LeafData]
    public let body: [Syntax]?
    public let userInfo: [AnyHashable: Any]

    init(
        _ parameters: [LeafData],
        _ data: [String: LeafData],
        _ body: [Syntax]?,
        _ userInfo: [AnyHashable: Any]
    ) throws {
        self.parameters = parameters
        self.data = data
        self.body = body
        self.userInfo = userInfo
    }

    /// Throws an error if the parameter count does not equal the supplied number `n`.
    public func requireParameterCount(_ n: Int) throws { __MajorBug("LeafContext deprecated") }

    /// Throws an error if this tag does not include a body.
    public func requireBody() throws -> [Syntax] { __MajorBug("LeafContext deprecated") }

    /// Throws an error if this tag includes a body.
    public func requireNoBody() throws { __MajorBug("LeafContext deprecated") }
}

@available(*, deprecated, message: "Register with LeafConfiguration.entities before running")
public var defaultTags: [String: LeafTag] = [:]
