internal extension LeafEntities {
    func registerStringReturns() {
        use(StrToStrMap.uppercased, asMethod: "uppercased")
        use(StrToStrMap.lowercased, asMethod: "lowercased")
        use(StrToStrMap.reversed, asMethod: "reversed")
        use(StrToStrMap.randomElement, asMethod: "randomElement")
        use(StrStrStrToStrMap.replace, asMethod: "replace")
        
        use(StrToStrMap.escapeHTML, asFunctionAndMethod: "escapeHTML")
    }
}

/// (String) -> String
internal struct StrToStrMap: LKMapMethod, StringReturn {
    static let callSignature: CallParameters = [.string]

    func evaluate(_ params: CallValues) -> LKData { .string(f(params[0].string!)) }
    
    private init(_ map: @escaping (String) -> String?) { f = map }
    private let f: (String) -> String?
    
    static let uppercased: Self = .init({ $0.uppercased() })
    static let lowercased: Self = .init({ $0.lowercased() })
    static let reversed: Self = .init({ String($0.reversed()) })
    static let randomElement: Self = .init({ $0.isEmpty ? nil : String($0.randomElement()!) })
    static let escapeHTML: Self = .init({ $0.reduce(into: "", {$0.append(basicHTML[$1] ?? $1.description)}) })
    
    private static let basicHTML: [Character: String] = [
        .lessThan: "&lt;", .greaterThan: "&gt;", .ampersand: "&amp;", .quote: "&quot;", .apostrophe: "&apos;"
    ]
}

internal struct StrStrStrToStrMap: LKMapMethod, StringReturn {
    static let callSignature: CallParameters = [
        .string, .string(labeled: "occurencesOf"), .string(labeled: "with")
    ]
    
    func evaluate(_ params: CallValues) -> LKData {
        .string(f(params[0].string!, params[1].string!, params[2].string!)) }
    
    private init(_ map: @escaping (String, String, String) -> String) { f = map }
    private let f: (String, String, String) -> String
    
    static let replace: Self = .init({ $0.replacingOccurrences(of: $1, with: $2) })
    
}
