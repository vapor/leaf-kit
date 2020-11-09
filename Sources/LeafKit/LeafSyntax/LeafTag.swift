import Foundation

public protocol LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData
}

public var defaultTags: [String: LeafTag] = [
    "lowercased": Lowercased(),
    "uppercased": Uppercased(),
    "capitalized": Capitalized(),
    "contains": Contains(),
    "date": DateTag(),
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

struct DateTag: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        let formatter = DateFormatter()
        switch ctx.parameters.count {
        case 1: formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        case 2:
            guard let string = ctx.parameters[1].string else {
                throw "Unable to convert date format to string"
            }
            formatter.dateFormat = string
        default:
            throw "invalid parameters provided for date"
        }

        guard let dateAsDouble = ctx.parameters.first?.double else {
            throw "Unable to convert parameter to double for date"
        }
        let date = Date(timeIntervalSince1970: dateAsDouble)

        let dateAsString = formatter.string(from: date)
        return LeafData.string(dateAsString)
    }
}
