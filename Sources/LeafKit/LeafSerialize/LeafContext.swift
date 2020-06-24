// MARK: Subject to change prior to 1.0.0 release
// MARK: -

public struct LeafContext {
    public let parameters: [LeafData]
    public let data: [String: LeafData]
    public let body: [Syntax]?
    public let userInfo: [AnyHashable: Any]

    init(
        parameters: [LeafData],
        data: [String: LeafData],
        body: [Syntax]?,
        userInfo: [AnyHashable: Any]
    ) throws {
        self.parameters = parameters
        self.data = data
        self.body = body
        self.userInfo = userInfo
    }

    /// Throws an error if the parameter count does not equal the supplied number `n`.
    public func requireParameterCount(_ n: Int) throws {
        guard parameters.count == n else {
            throw "Invalid parameter count: \(parameters.count)/\(n)"
        }
    }

    /// Throws an error if this tag does not include a body.
    public func requireBody() throws -> [Syntax] {
        guard let body = body else {
            throw "Missing body"
        }

        return body
    }

    /// Throws an error if this tag includes a body.
    public func requireNoBody() throws {
        guard body == nil else {
            throw "Extraneous body"
        }
    }
}
