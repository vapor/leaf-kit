struct ResolvedParameter {
    let param: ProcessedParameter
    let result: TemplateData
}

struct ParameterResolver {
    let context: [String: TemplateData]
    let params: [ProcessedParameter]
    
    func resolve() throws -> [ResolvedParameter] {
        return try params.map(resolve)
    }
    
    private func resolve(_ param: ProcessedParameter) throws -> ResolvedParameter {
        let result: TemplateData
        switch param {
        case .expression(let e):
            result = try resolve(expression: e)
        case .parameter(let p):
            result = try resolve(param: p)
        case .tag(let t):
            result = try customTags[t.name]?.render(params: t.params, body: t.body, context: context)
                ?? .init(.null)
        }
        return .init(param: param, result: result)
    }
    
    private func resolve(param: Parameter) throws -> TemplateData {
        switch param {
        case .constant(let c):
            switch c {
            case .double(let d): return TemplateData(.double(d))
            case .int(let d): return TemplateData(.int(d))
            }
        case .stringLiteral(let s):
            return .init(.string(s))
        case .variable(let v):
            return context[v] ?? .init(.null)
        case .keyword(let k):
            switch k {
            case .self: return .init(.dictionary(context))
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
    private func resolve(expression: [ProcessedParameter]) throws -> TemplateData {
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
    
    private func resolve(lhs: TemplateData, op: Operator, rhs: TemplateData) throws -> TemplateData {
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
        case .plus, .minus, .multiply, .divide:
            fatalError("concat string, add nums")
        }
    }
    
    private func resolve(lhs: TemplateData, key: Keyword, rhs: TemplateData) throws -> TemplateData {
        switch key {
        case .in:
            let arr = rhs.array ?? []
            return .init(.bool(arr.contains(lhs)))
        default:
            return .init(.null)
        }
    }
}
