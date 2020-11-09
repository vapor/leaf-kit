public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
    "uppercased": Uppercased(),
    "capitalized": Capitalized(),
    "contains": Contains(),
]

struct Lowercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to lowercase unexpected data"
        }
        return .init(.string(str.lowercased()))
    }
}

struct Uppercased: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to uppercase unexpected data"
        }
        return .init(.string(str.uppercased()))
    }
}

struct Capitalized: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let str = ctx.parameters.first?.string else {
            throw "unable to capitalize unexpected data"
        }
        return .init(.string(str.capitalized))
    }
}

struct Contains: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(2)
        guard let collection = ctx.parameters[0].array else {
            throw "unable to convert first parameter to array"
        }
        let result = collection.contains(ctx.parameters[1])
        return .init(.bool(result))
    }
}
