public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased()
]

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to lowercase unexpected data"
        }
        return .init(.string(str.lowercased()))
    }
}
