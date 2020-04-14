public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
    "index": LoopIndex(),
    "isFirst": LoopIsFirst(),
    "isLast": LoopIsLast()
]

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to lowercase unexpected data"
        }
        return .init(.string(str.lowercased()))
    }
}

struct LoopIndex: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let index = ctx.data["index"] else { throw "Loop accessor called on non-loop" }
        return index
    }
}

struct LoopIsFirst: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let isFirst = ctx.data["isFirst"] else { throw "Loop accessor called on non-loop" }
        return isFirst
    }
}

struct LoopIsLast: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let isLast = ctx.data["isLast"] else { throw "Loop accessor called on non-loop" }
        return isLast
    }
}
