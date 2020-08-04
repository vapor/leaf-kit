// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

// TODO: Move to a better location
public extension Dictionary where Key == String, Value == LeafData {
    subscript(keyPath keyPath: String) -> LeafData? {
        let comps = keyPath.split(separator: ".").map(String.init)
        return self[keyPath: comps]
    }

    subscript(keyPath comps: [String]) -> LeafData? {
        if comps.isEmpty { return nil }
        else if comps.count == 1 { return self[comps[0]] }

        var comps = comps
        let key = comps.removeFirst()
        guard let val = self[key]?.dictionary else { return nil }
        return val[keyPath: comps]
    }
}

internal extension ParameterDeclaration {
    var `operator`: LeafOperator? {
        guard case .parameter(let p) = self,
              case .operator(let op) = p else { return nil }
        return op
    }
}

internal struct ParameterResolver {
    internal init(_ params: [ParameterDeclaration],
                  _ data: [String : LeafData],
                  _ tags: [String : LeafTag],
                  _ userInfo: [AnyHashable : Any]) {
        self.params = params
        self.data = data
        self.tags = tags
        self.userInfo = userInfo
    }
    
    
    // MARK: - Internal Only
    
    let params: [ParameterDeclaration]
    let data: [String: LeafData]
    let tags: [String: LeafTag]
    let userInfo: [AnyHashable: Any]

    func resolve() throws -> [ResolvedParameter] { try params.map(resolve) }

    internal struct ResolvedParameter {
        let param: ParameterDeclaration
        let result: LeafData
    }
    
    // MARK: - Private Only

    private func resolve(_ param: ParameterDeclaration) throws -> ResolvedParameter {
        let result: LeafData
        switch param {
            case .expression(let e)  : result = try resolve(expression: e)
            case .parameter(let p)   : result = try resolve(param: p)
            case .tag(let t):
                let resolver = ParameterResolver(t.params, data, tags, userInfo)
                let tagParams = try resolver.resolve().map {$0.result}
                let ctx = try LeafContext(tagParams, data, t.body, userInfo)
                result = try tags[t.name]?.render(ctx) ?? .trueNil
        }
        return .init(param: param, result: result)
    }

    private func resolve(param: LeafTokenParameter) throws -> LeafData {
        switch param {
            case .literal(let c):
                switch c {
                    case .double(let d) : return d.leafData
                    case .int(let i)    : return i.leafData
                    case .string(let s) : return s.leafData
                    case .emptyArray    : return .array([])
                }
            case .variable(var v):
                if v == "$context" { return data.leafData }
                if !v.hasPrefix("$") { return data[keyPath: v] ?? .trueNil }
                if (v.hasPrefix("$.")) || (v.hasPrefix("$context.")) {
                    v = String(v.split(maxSplits: 1) { $0 == "."}[1])
                }
                return data[keyPath: v] ?? .trueNil
            case .keyword(let k):
                switch k {
                    case .nil         : return .trueNil
                    case .true, .yes  : return .init(.bool(true))
                    case .false, .no  : return .init(.bool(false))
                    case .in, .`self`, ._, .leaf : throw "unexpected keyword"
                        // Self should have converted to variable before now
                }
            // these should all have been removed in processing
            case .function: throw "unexpected tag"
            case .operator: throw "unexpected operator"
        }
    }

    // #if(lowercase(first(name == "admin")) == "welcome")
    private func resolve(expression: [ParameterDeclaration]) throws -> LeafData {
        switch expression.count {
            case 0: throw "Unexpected empty expression"
            case 1: return try resolve(expression[0]).result
            case 2:
                if let lho = expression[0].operator,
                   let rhs = try? resolve(expression[1]).result {
                    return try resolve(op: lho, rhs: rhs)
                } else if expression[1].operator != nil {
                    throw "No postfix operators currently supported"
                } else { throw "Unexpected expression with no operators: \(expression)" }
            case 3:
                let lhs = try resolve(expression[0]).result
                let functor = expression[1]
                let rhs = try resolve(expression[2]).result
                guard case .parameter(let p) = functor else { throw "expected keyword or operator" }
                switch p {
                    case .keyword(let k)  : return try resolve(lhs: lhs, key: k, rhs: rhs)
                    case .operator(let o) : return try resolve(lhs: lhs, op: o, rhs: rhs)
                    default: throw "Unsupported - parameter: \(p)"
                }
            default: throw "Unsupported complex expression: \(expression)"
        }
    }

    private func resolve(op: LeafOperator, rhs: LeafData) throws -> LeafData {
        switch op {
            case .not   : return .bool(!(rhs.bool ?? !rhs.isNil))
            case .minus : return try resolve(lhs: -1, op: .multiply, rhs: rhs)
            default: throw "Unexpected prefix operator: \(op)"
        }
    }

    private func resolve(lhs: LeafData, op: LeafOperator, rhs: LeafData) throws -> LeafData {
        switch op {
            case .not:   throw "single expression operator"
            case .and, .or:
                let lhs = lhs.bool ?? !lhs.isNil
                let rhs = rhs.bool ?? !rhs.isNil
                return op == .and ? .bool(lhs && rhs) : .bool(lhs || rhs)
            case .equal, .unequal:
                return op == .equal ? .bool(lhs == rhs) : .bool(lhs != rhs)
            case .lesser:
                guard let lhs = lhs.string, let rhs = rhs.string else { return .trueNil }
                if let lhs = Double(lhs),
                   let rhs = Double(rhs) { return .bool(lhs < rhs) }
                                    else { return .bool(lhs < rhs) }
            case .lesserOrEqual:
                guard let lhs = lhs.string, let rhs = rhs.string else { return .trueNil }
                if let lhs = Double(lhs),
                   let rhs = Double(rhs) { return .bool(lhs <= rhs) }
                                    else { return .bool(lhs <= rhs) }
            case .greater:
                guard let lhs = lhs.string, let rhs = rhs.string else { return .trueNil }
                if let lhs = Double(lhs),
                   let rhs = Double(rhs) { return .bool(lhs > rhs) }
                                    else { return .bool(lhs > rhs) }
            case .greaterOrEqual:
                guard let lhs = lhs.string, let rhs = rhs.string else { return .trueNil }
                if let lhs = Double(lhs),
                   let rhs = Double(rhs) { return .init(.bool(lhs >= rhs)) }
                                    else { return .init(.bool(lhs >= rhs)) }
            case .plus:                    return try plus(lhs: lhs, rhs: rhs)
            case .minus:                   return try minus(lhs: lhs, rhs: rhs)
            case .multiply:                return try multiply(lhs: lhs, rhs: rhs)
            case .divide:                  return try divide(lhs: lhs, rhs: rhs)
            case .assignment, .nilCoalesce, .modulo, .evaluate,
                 .scopeRoot, .scopeMember, .subOpen, .subClose,
                 .xor, .subScript: throw "Future feature"
        }
    }

    private func plus(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.container {
            case .array(let arr)    : return .array(arr + (rhs.array ?? []))
            case .data(let data)    : return .data(data + (rhs.data ?? Data()))
            case .string(let s)     : return .string(s + (rhs.string ?? ""))
            case .double(let d)     : return .double(d + (rhs.double ?? 0))
            case .lazy(let f, _, _) : return try plus(lhs: f(), rhs: rhs)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.container {
                    return .double(Double(i) + d)
                } else {
                    let added = i.addingReportingOverflow(rhs.int ?? 0)
                    guard !added.overflow else { throw "Integer overflow" }
                    return .int(added.partialValue)
                }
            case .dictionary(let lhs):
                var rhs = rhs.dictionary ?? [:]
                lhs.forEach { key, val in rhs[key] = val }
                return .init(.dictionary(rhs))
            case .optional: throw "Optional unwrapping not possible yet"
            case .bool: throw "Boolen + `\(rhs)' unmeaningful: Did you mean &&"
        }
    }

    private func minus(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.container {
            case .double(let d)     : return .double(d - (rhs.double ?? 0))
            case .lazy(let f, _, _) : return try minus(lhs: f(), rhs: rhs)
            case .optional(_, _)    : throw "Optional unwrapping not possible yet"
            case .array(let arr):
                let rhs = rhs.array ?? []
                let new = arr.filter { !rhs.contains($0) }
                return .array(new)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.container {
                    return .double(Double(i) - d)
                } else {
                    let subtracted = i.subtractingReportingOverflow(rhs.int ?? 0)
                    guard !subtracted.overflow else { throw "Integer underflow" }
                    return .int(subtracted.partialValue)
                }
            case .data, .string, .dictionary, .bool:
                throw "unable to subtract from \(lhs)"
        }
    }

    private func multiply(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.container {
            case .optional(_, _)    : throw "Optional unwrapping not possible yet"
            case .double(let d)     : return .double(d * (rhs.double ?? 0))
            case .lazy(let f, _, _) : return try multiply(lhs: f(), rhs: rhs)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.container {
                    return .double(Double(i) * d)
                } else { return .int(i * (rhs.int ?? 0)) }
            case .data, .array, .string, .dictionary, .bool:
                throw "unable to multiply this type `\(lhs)`"
        }
    }

    private func divide(lhs: LeafData, rhs: LeafData) throws -> LeafData {
        switch lhs.container {
            case .optional(_, _)    : throw "Optional unwrapping not possible yet"
            case .double(let d)     : return .double(d / (rhs.double ?? 0))
            case .lazy(let f, _, _) : return try divide(lhs: f(), rhs: rhs)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.container {
                         return .double(Double(i) / d)
                } else { return .int(i / (rhs.int ?? 0)) }
            case .data, .array, .string, .dictionary, .bool:
                throw "unable to multiply this type `\(lhs)`"
        }
    }

    private func resolve(lhs: LeafData, key: LeafKeyword, rhs: LeafData) throws -> LeafData {
        switch key {
            case .in: return .init(.bool((rhs.array ?? []).contains(lhs)))
            default:  return .trueNil
        }
    }
}
