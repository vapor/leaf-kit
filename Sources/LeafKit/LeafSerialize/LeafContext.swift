public struct LeafContext {
    public let tag: String
    public let parameters: [LeafData]
    public let data: [String: LeafData]
    public let body: [Statement]?
    public let userInfo: [AnyHashable: Any]

    init(
        tag: String,
        parameters: [LeafData],
        data: [String: LeafData],
        body: [Statement]?,
        userInfo: [AnyHashable: Any]
    ) throws {
        self.tag = tag
        self.parameters = parameters
        self.data = data
        self.body = body
        self.userInfo = userInfo
    }

    /// Throws an error if the parameter count does not equal the supplied number `n`.
    public func requireParameterCount(_ n: Int) throws {
        guard parameters.count == n else {
            throw LeafError(.badParameterCount(tag: tag, expected: n, got: parameters.count))
        }
    }

    /// Throws an error if this tag does not include a body.
    public func requireBody() throws -> [Statement] {
        guard let body = body else {
            throw LeafError(.missingBody(tag: tag))
        }

        return body
    }

    /// Throws an error if this tag includes a body.
    public func requireNoBody() throws {
        guard body == nil else {
            throw LeafError(.extraneousBody(tag: tag))
        }
    }
}
