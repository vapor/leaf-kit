import Foundation

extension ParameterDeclaration {
    func `operator`() -> LeafOperator? {
        guard case .parameter(.operator(let o)) = self else {
            return nil
        }
        return o
    }
}

struct ParameterResolver {
    // MARK: - Internal Only
    
    let params: [ParameterDeclaration]
    let data: [String: LeafData]
    let tags: [String: any LeafTag]
    let userInfo: [AnyHashable: Any]

    func resolve() throws -> [ResolvedParameter] {
        try self.params.map(resolve)
    }

    struct ResolvedParameter {
        let param: ParameterDeclaration
        let result: LeafData
    }
    
    // MARK: - Private Only

    private func resolve(_ param: ParameterDeclaration) throws -> ResolvedParameter {
        let result: LeafData
        switch param {
            case .expression(let e):
                result = try self.resolve(expression: e)
            case .parameter(let p):
                result = try self.resolve(param: p)
            case .tag(let t):
                let resolver = ParameterResolver(
                    params: t.params,
                    data: self.data,
                    tags: self.tags,
                    userInfo: self.userInfo
                )
                let ctx = try LeafContext(
                    parameters: resolver.resolve().map { $0.result },
                    data: data,
                    body: t.body,
                    userInfo: self.userInfo
                )
                result = try self.tags[t.name]?.render(ctx) ?? .trueNil
        }
        return .init(param: param, result: result)
    }

    private func resolve(param: Parameter) throws -> LeafData {
        switch param {
        case .constant(let c):
            switch c {
            case .double(let d):
                LeafData(.double(d))
            case .int(let d):
                LeafData(.int(d))
            }
        case .stringLiteral(let s):
            .init(.string(s))
        case .variable(let v):
            self.data[keyPath: v] ?? .trueNil
        case .keyword(let k):
            switch k {
                case .this: .init(.dictionary(self.data))
                case .nil: .trueNil
                case .true, .yes: .init(.bool(true))
                case .false, .no: .init(.bool(false))
                default: throw LeafError(.unknownError("unexpected keyword"))
            }
        // these should all have been removed in processing
        case .tag:
            throw LeafError(.unknownError("unexpected tag"))
        case .operator:
            throw LeafError(.unknownError("unexpected operator"))
        }
    }

    // #if(lowercase(first(name == "admin")) == "welcome")
    private func resolve(expression: [ParameterDeclaration]) throws -> LeafData {
        if expression.count == 1 {
            return try self.resolve(expression[0]).result
        } else if expression.count == 2 {
            if let lho = expression[0].operator() {
                let rhs = try self.resolve(expression[1]).result
                return try self.resolve(op: lho, rhs: rhs)
            } else if let _ = expression[1].operator() {
                throw LeafError(.unknownError("right hand expressions not currently supported"))
            } else {
                throw LeafError(.unknownError("two part expression expected to include at least one operator"))
            }
        } else if expression.count == 3 {
            // file == name + ".jpg"
            // should resolve to:
            // param(file) == expression(name + ".jpg")
            // based on priorities in such a way that each expression
            // is 3 variables, lhs, functor, rhs
            guard expression.count == 3 else {
                throw LeafError(.unknownError("multiple expressions not currently supported: \(expression)"))
            }
            let lhs = try self.resolve(expression[0]).result
            let functor = expression[1]
            let rhs = try self.resolve(expression[2]).result
            guard case .parameter(let p) = functor else {
                throw LeafError(.unknownError("expected keyword or operator"))
            }
            switch p {
            case .keyword(let k):
                return try self.resolve(lhs: lhs, key: k, rhs: rhs)
            case .operator(let o):
                return try self.resolve(lhs: lhs, op: o, rhs: rhs)
            default:
                throw LeafError(.unknownError("unexpected parameter: \(p)"))
            }
        } else {
            throw LeafError(.unknownError("unsupported expression, expected 2 or 3 components: \(expression)"))
        }
    }

    private func resolve(op: LeafOperator, rhs: LeafData) throws -> LeafData {
        switch op {
        case .not:
            let result = rhs.bool ?? !rhs.isNil
            return .bool(!result)
        case .minus:
            return try self.resolve(lhs: -1, op: .multiply, rhs: rhs)
        default:
            throw LeafError(.unknownError("unexpected left hand operator not supported: \(op)"))
        }
    }

    private func resolve(lhs: LeafData, op: LeafOperator, rhs: LeafData) throws -> LeafData {
        switch op {
        case .not:
            throw LeafError(.unknownError("single expression operator"))
        case .and:
            let lhs = lhs.bool ?? !lhs.isNil
            let rhs = rhs.bool ?? !rhs.isNil
            return .bool(lhs && rhs)
        case .or:
            let lhs = lhs.bool ?? !lhs.isNil
            let rhs = rhs.bool ?? !rhs.isNil
            return .bool(lhs || rhs)
        case .equal:
            return .bool(lhs == rhs)
        case .unequal:
            return .bool(lhs != rhs)
        case .lesser:
            guard let lhs = lhs.string, let rhs = rhs.string else { return LeafData.trueNil }
            if let lhs = Double(lhs), let rhs = Double(rhs) {
                return .bool(lhs < rhs)
            } else {
                return .bool(lhs < rhs)
            }
        case .lesserOrEqual:
            guard let lhs = lhs.string, let rhs = rhs.string else { return LeafData.trueNil }
            if let lhs = Double(lhs), let rhs = Double(rhs) {
                return .bool(lhs <= rhs)
            } else {
                return .bool(lhs <= rhs)
            }
        case .greater:
            guard let lhs = lhs.string, let rhs = rhs.string else { return LeafData.trueNil }
            if let lhs = Double(lhs), let rhs = Double(rhs) {
                return .bool(lhs > rhs)
            } else {
                return .bool(lhs > rhs)
            }
        case .greaterOrEqual:
            guard let lhs = lhs.string, let rhs = rhs.string else { return LeafData.trueNil }
            if let lhs = Double(lhs), let rhs = Double(rhs) {
                return .init(.bool(lhs >= rhs))
            } else {
                return .init(.bool(lhs >= rhs))
            }
        case .plus:
            return try self.plus(lhs: lhs, rhs: rhs)
        case .minus:
            return try self.minus(lhs: lhs, rhs: rhs)
        case .multiply:
            return try self.multiply(lhs: lhs, rhs: rhs)
        case .divide:
            return try self.divide(lhs: lhs, rhs: rhs)
        case .modulo:
            return try self.modulo(lhs: lhs, rhs: rhs)
        case .assignment: throw LeafError(.unknownError("Future feature"))
        case .nilCoalesce: throw LeafError(.unknownError("Future feature"))
        case .evaluate: throw LeafError(.unknownError("Future feature"))
        case .scopeRoot: throw LeafError(.unknownError("Future feature"))
        case .scopeMember: throw LeafError(.unknownError("Future feature"))
        case .subOpen: throw LeafError(.unknownError("Future feature"))
        case .subClose: throw LeafError(.unknownError("Future feature"))
        }
    }

    private func plus(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
        case .array(let arr):
            let rhs = rhs.array ?? []
            return .array(arr + rhs)
        case .data(let data):
            let rhs = rhs.data ?? Data()
            return .data(data + rhs)
        case .string(let s):
            let rhs = rhs.string ?? ""
            return .string(s + rhs)
        case .int(let i):
            // if either is double, be double
            if case .double(let d) = rhs.storage {
                let sum = Double(i) + d
                return .double(sum)
            } else {
                let rhs = rhs.int ?? 0
                let added = i.addingReportingOverflow(rhs)
                guard !added.overflow else {
                    throw LeafError(.unknownError("Integer overflow"))
                }
                return .int(added.partialValue)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d + rhs)
        case .dictionary(let lhs):
            var rhs = rhs.dictionary ?? [:]
            lhs.forEach { key, val in
                rhs[key] = val
            }
            return .init(.dictionary(rhs))

        case .optional(_, _):
            throw LeafError(.unknownError("Optional unwrapping not possible yet"))
        case .bool(let b):
            throw LeafError(.unknownError("unable to concatenate bool `\(b)` with `\(rhs)', maybe you meant &&"))
        }
    }

    private func minus(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
        case .optional(_, _):
            throw LeafError(.unknownError("Optional unwrapping not possible yet"))
        case .array(let arr):
            let rhs = rhs.array ?? []
            let new = arr.filter { !rhs.contains($0) }
            return .array(new)
        case .int(let i):
            // if either is double, be double
            if case .double(let d) = rhs.storage {
                let oppositeOfSum = Double(i) - d
                return .double(oppositeOfSum)
            } else {
                let rhs = rhs.int ?? 0
                let subtracted = i.subtractingReportingOverflow(rhs)
                guard !subtracted.overflow else {
                    throw LeafError(.unknownError("Integer underflow"))
                }
                return .int(subtracted.partialValue)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d - rhs)
        case .data, .string, .dictionary, .bool:
            throw LeafError(.unknownError("unable to subtract from \(lhs)"))
        }
    }

    private func multiply(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
        case .optional(_, _):
            throw LeafError(.unknownError("Optional unwrapping not possible yet"))
        case .int(let i):
            // if either is double, be double
            if case .double(let d) = rhs.storage {
                let product = Double(i) * d
                return .double(product)
            } else {
                let rhs = rhs.int ?? 0
                return .int(i * rhs)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d * rhs)
        case .data, .array, .string, .dictionary, .bool:
            throw LeafError(.unknownError("unable to multiply this type `\(lhs)`"))
        }
    }

    private func divide(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
        case .optional(_, _):
            throw LeafError(.unknownError("Optional unwrapping not possible yet"))
        case .int(let i):
            // if either is double, be double
            if case .double(let d) = rhs.storage {
                let product = Double(i) / d
                return .double(product)
            } else {
                let rhs = rhs.int ?? 0
                return .int(i / rhs)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d / rhs)
        case .data, .array, .string, .dictionary, .bool:
            throw LeafError(.unknownError("unable to divide this type `\(lhs)`"))
        }
    }
    
    private func modulo(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
        case .optional(_, _):
            throw LeafError(.unknownError("Optional unwrapping not possible yet"))
        case .int(let i):
            // if either is double, be double
            if case .double(let d) = rhs.storage {
                let product = Double(i).truncatingRemainder(dividingBy: d)
                return .double(product)
            } else {
                let rhs = rhs.int ?? 0
                return .int(i % rhs)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d.truncatingRemainder(dividingBy: rhs))
        case .data, .array, .string, .dictionary, .bool:
            throw LeafError(.unknownError("unable to apply modulo on this type `\(lhs)`"))
        }
    }

    private func resolve(lhs: LeafData, key: LeafKeyword, rhs: LeafData) throws -> LeafData {
        switch key {
        case .in:
            let arr = rhs.array ?? []
            return .init(.bool(arr.contains(lhs)))
        default:
            return .trueNil
        }
    }
}
