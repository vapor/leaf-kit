import Foundation

struct ResolvedParameter {
    let param: ParameterDeclaration
    let result: LeafData
}

struct ParameterResolver {
    let params: [ParameterDeclaration]
    let data: [String: LeafData]
    
    func resolve() throws -> [ResolvedParameter] {
        return try params.map(resolve)
    }
    
    private func resolve(_ param: ParameterDeclaration) throws -> ResolvedParameter {
        let result: LeafData
        switch param {
        case .expression(let e):
            result = try resolve(expression: e)
        case .parameter(let p):
            result = try resolve(param: p)
        case .tag(let t):
            let ctx = LeafContext(params: t.params, data: data, body: t.body)
            result = try customTags[t.name]?.render(ctx)
                ?? .init(.null)
        }
        return .init(param: param, result: result)
    }
    
    private func resolve(param: Parameter) throws -> LeafData {
        switch param {
        case .constant(let c):
            switch c {
            case .double(let d): return LeafData(.double(d))
            case .int(let d): return LeafData(.int(d))
            }
        case .stringLiteral(let s):
            return .init(.string(s))
        case .variable(let v):
            return data[v] ?? .init(.null)
        case .keyword(let k):
            switch k {
            case .self: return .init(.dictionary(data))
            case .nil: return .init(.null)
            case .true, .yes: return .init(.bool(true))
            case .false, .no: return .init(.bool(false))
            default: throw "unexpected keyword"
            }
        // these should all have been removed in processing
        case .tag: throw "unexpected tag"
        case .operator: throw "unexpected operator"
        case .expression: throw "unexpected expression"
        }
    }
    
    // #if(lowercase(first(name == "admin")) == "welcome")
    private func resolve(expression: [ParameterDeclaration]) throws -> LeafData {
        // todo: to support nested expressions, ie:
        // file == name + ".jpg"
        // should resolve to:
        // param(file) == expression(name + ".jpg")
        // based on priorities in such a way that each expression
        // is 3 variables, lhs, functor, rhs
        guard expression.count == 3 else { throw "multiple expressions not currently supported" }
        let lhs = try resolve(expression[0]).result
        let functor = expression[1]
        let rhs = try resolve(expression[2]).result
        guard case .parameter(let p) = functor else { throw "expected keyword or operator" }
        switch p {
        case .keyword(let k):
            return try resolve(lhs: lhs, key: k, rhs: rhs)
        case .operator(let o):
            return try resolve(lhs: lhs, op: o, rhs: rhs)
        default:
            throw "unexpected parameter: \(p)"
        }
    }
    
    private func resolve(lhs: LeafData, op: Operator, rhs: LeafData) throws -> LeafData {
        switch op {
        case .and:
            let lhs = lhs.bool ?? false
            let rhs = rhs.bool ?? false
            return .init(.bool(lhs && rhs))
        case .or:
            let lhs = lhs.bool ?? false
            let rhs = rhs.bool ?? false
            return .init(.bool(lhs || rhs))
        case .equals:
            return .init(.bool(lhs == rhs))
        case .notEquals:
            return .init(.bool(lhs != rhs))
        case .lessThan:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs < rhs))
        case .lessThanOrEquals:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs <= rhs))
        case .greaterThan:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs > rhs))
        case .greaterThanOrEquals:
            guard let lhs = lhs.string, let rhs = rhs.string else { return .init(.null) }
            return .init(.bool(lhs >= rhs))
        case .plus:
            return try plus(lhs: lhs, rhs: rhs)
        case .minus:
            return try minus(lhs: lhs, rhs: rhs)
        case .multiply:
            return try multiply(lhs: lhs, rhs: rhs)
        case .divide:
            return try divide(lhs: lhs, rhs: rhs)
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
                return .int(i + rhs)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d + rhs)
        case .lazy(let load):
            let l = load()
            return try plus(lhs: l, rhs: rhs)
        case .dictionary(let lhs):
            var rhs = rhs.dictionary ?? [:]
            lhs.forEach { key, val in
                rhs[key] = val
            }
            return .init(.dictionary(rhs))
        case .null:
            throw "unable to concatenate `null` with `\(rhs)'"
        case .bool(let b):
            throw "unable to concatenate bool `\(b)` with `\(rhs)', maybe you meant &&"
        }
    }
    
    private func minus(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
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
                return .int(i - rhs)
            }
        case .double(let d):
            let rhs = rhs.double ?? 0
            return .double(d - rhs)
        case .lazy(let load):
            let l = load()
            return try minus(lhs: l, rhs: rhs)
        case .data, .string, .dictionary, .null, .bool:
            throw "unable to subtract from \(lhs)"
        }
    }
    
    private func multiply(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
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
        case .lazy(let load):
            let l = load()
            return try multiply(lhs: l, rhs: rhs)
        case .data, .array, .string, .dictionary, .null, .bool:
            throw "unable to multiply this type `\(lhs)`"
        }
    }
    
    private func divide(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.storage {
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
        case .lazy(let load):
            let l = load()
            return try divide(lhs: l, rhs: rhs)
        case .data, .array, .string, .dictionary, .null, .bool:
            throw "unable to multiply this type `\(lhs)`"
        }
    }
    
    private func resolve(lhs: LeafData, key: Keyword, rhs: LeafData) throws -> LeafData {
        switch key {
        case .in:
            let arr = rhs.array ?? []
            return .init(.bool(arr.contains(lhs)))
        default:
            return .init(.null)
        }
    }
}
