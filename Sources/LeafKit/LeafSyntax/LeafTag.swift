// MARK: Subject to change prior to 1.0.0 release
// MARK: -

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

public var defaultTags: [String: LeafTag] = [:]
