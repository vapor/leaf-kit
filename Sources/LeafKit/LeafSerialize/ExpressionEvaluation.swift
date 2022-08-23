import Foundation

func identity<T>(_ val: T) -> ((T, T) -> T) {
    return { _, _ in val }
}

func selfToSelf(
    _ val: LeafData,
    _ doubleFunction: (Double) -> Double,
    _ intFunction: (Int) -> Int
) throws -> LeafData {
    if let val = val.int {
        return .int(intFunction(val))
    } else if let val = val.double {
        return .double(doubleFunction(val))
    } else {
        throw LeafError(.expectedNumeric(got: val.concreteType ?? .void))
    }
}

func selfAndSelfToSelf(
    _ lhs: LeafData,
    _ rhs: LeafData,
    _ doubleFunction: (Double, Double) -> Double?,
    _ intFunction: (Int, Int) -> Int?,
    _ stringFunction: (String, String) -> String?,
    _ what: String
) throws -> LeafData {
    func unwrap<T>(_ kind: LeafData.NaturalType, _ val: T?) throws -> T {
        guard let trueVal = val else {
            throw LeafError(.badOperation(on: kind, what: what))
        }
        return trueVal
    }

    if let lhs = lhs.int, let rhs = rhs.int {
        return .int(try unwrap(.int, intFunction(lhs, rhs)))
    } else if let lhs = lhs.double, let rhs = rhs.double {
        return .double(try unwrap(.double, doubleFunction(lhs, rhs)))
    } else if let lhs = lhs.string, let rhs = rhs.string {
        return .string(try unwrap(.string, stringFunction(lhs, rhs)))
    } else {
        return .trueNil
    }
}

func compare(
    _ lhs: LeafData,
    _ rhs: LeafData,
    _ doubleCompare: (Double, Double) -> Bool,
    _ stringCompare: (String, String) -> Bool
) -> LeafData {
    guard let lhs = lhs.string, let rhs = rhs.string else { return LeafData.trueNil }
    if let lhs = Double(lhs), let rhs = Double(rhs) {
        return .bool(doubleCompare(lhs, rhs))
    } else {
        return .bool(stringCompare(lhs, rhs))
    }
}

func evaluateExpression(
    expression: Expression,
    data: [String: LeafData],
    tags: [String: LeafTag],
    userInfo: [AnyHashable: Any]
) throws -> LeafData {
    let eval = { expr in
        return try evaluateExpression(expression: expr, data: data, tags: tags, userInfo: userInfo)
    }
    switch expression.kind {
    case .boolean(let val as LeafDataRepresentable),
        .integer(let val as LeafDataRepresentable),
        .float(let val as LeafDataRepresentable),
        .string(let val as LeafDataRepresentable):
        return val.leafData
    case .variable(let name):
        return data[String(name)] ?? .trueNil
    case .binary(let eLhs, let op, let eRhs):
        let lhs = try eval(eLhs)
        let rhs = try eval(eRhs)

        switch (lhs, op, rhs) {
        case (_, .unequal, _):
            return compare(lhs, rhs, (!=), (!=))
        case (_, .equal, _):
            return compare(lhs, rhs, (==), (==))
        case (_, .greater, _):
            return compare(lhs, rhs, (>), (>))
        case (_, .greaterOrEqual, _):
            return compare(lhs, rhs, (>=), (>=))
        case (_, .lesser, _):
            return compare(lhs, rhs, (<), (<))
        case (_, .lesserOrEqual, _):
            return compare(lhs, rhs, (<=), (<=))
        case (_, .and, _):
            guard let lhsB = lhs.coerce(to: .bool).bool, let rhsB = rhs.coerce(to: .bool).bool else {
                switch (lhs.coerce(to: .bool).bool, rhs.coerce(to: .bool).bool) {
                case (_, nil):
                    throw LeafError(.typeError(shouldHaveBeen: .bool, got: rhs.concreteType ?? .void))
                case (nil, _):
                    throw LeafError(.typeError(shouldHaveBeen: .bool, got: lhs.concreteType ?? .void))
                default:
                    assert(false, "this should be impossible to reach")
                }
            }
            return .bool(lhsB && rhsB)
        case (_, .or, _):
            guard let lhsB = lhs.coerce(to: .bool).bool, let rhsB = rhs.coerce(to: .bool).bool else {
                switch (lhs.coerce(to: .bool).bool, rhs.coerce(to: .bool).bool) {
                case (_, nil):
                    throw LeafError(.typeError(shouldHaveBeen: .bool, got: rhs.concreteType ?? .void))
                case (nil, _):
                    throw LeafError(.typeError(shouldHaveBeen: .bool, got: lhs.concreteType ?? .void))
                default:
                    assert(false, "this should be impossible to reach")
                }
            }
            return .bool(lhsB || rhsB)
        case (_, .not, _):
            assert(false, "not operator (!) should never be parsed as infix")
        case (_, .plus, _):
            return try selfAndSelfToSelf(lhs, rhs, (+), (+), identity(nil), "addition")
        case (_, .minus, _):
            return try selfAndSelfToSelf(lhs, rhs, (-), (-), identity(nil), "subtraction")
        case (_, .divide, _):
            return try selfAndSelfToSelf(lhs, rhs, (/), (/), identity(nil), "division")
        case (_, .multiply, _):
            return try selfAndSelfToSelf(lhs, rhs, (*), (*), identity(nil), "multiplication")
        case (_, .modulo, _):
            return try selfAndSelfToSelf(lhs, rhs, identity(nil), (%), identity(nil), "modulo")
        case (_, .fieldAccess, _):
            assert(false, "this shouldn't be parsed as a binary operator")
        }
    case .unary(let op, let expr):
        assert(op.data.kind.prefix, "infix operator should never be parsed as prefix")
        let val = try eval(expr)
        switch op {
        case .not:
            return val.coerce(to: .bool).bool.map { .bool(!$0) } ?? .trueNil
        case .minus:
            return try selfToSelf(val, (-), (-))
        default:
            assert(false, "this unary operator should have been added to the unary evaluation")
        }
    case .tagApplication(let name, let params):
        guard let tag = tags[String(name)] else {
            throw LeafError(.tagNotFound(name: String(name)))
        }
        let evaluatedParams = try params.map { try eval($0) }
        return try tag.render(LeafContext(tag: String(name), parameters: evaluatedParams, data: data, body: nil, userInfo: userInfo))
    case .fieldAccess(let lhs, let field):
        let val = try eval(lhs)
        guard let dict = val.dictionary else {
            throw LeafError(.typeError(shouldHaveBeen: .dictionary, got: val.concreteType ?? .void))
        }
        return dict[String(field)] ?? .trueNil
    case .arrayLiteral(let items):
        return .array(try items.map { try eval($0) })
    case .dictionaryLiteral(let pairs):
        return .dictionary(Dictionary(try pairs.map { data -> (String, LeafData) in
            let (key, val) = data
            let keyData = try eval(key)
            let valData = try eval(val)
            guard let str = keyData.coerce(to: .string).string else {
                throw LeafError(.typeError(shouldHaveBeen: .string, got: keyData.concreteType ?? .void))
            }
            return (str, valData)
        }, uniquingKeysWith: { $1 }))
    }
}
