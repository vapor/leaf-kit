internal extension LeafEntities {
    func registerStringReturns() {
        use(StrToStrMap.uppercased, asMethod: "uppercased")
        use(StrToStrMap.lowercased, asMethod: "lowercased")
        use(StrToStrMap.reversed, asMethod: "reversed")
        use(StrToStrMap.randomElement, asMethod: "randomElement")
        use(StrStrStrToStrMap.replace, asMethod: "replace")
        
        use(StrToStrMap.escapeHTML, asFunctionAndMethod: "escapeHTML")
        
        use(DoubleFormatterMap.seconds, asFunctionAndMethod: "formatSeconds")
        use(IntFormatterMap.bytes, asFunctionAndMethod: "formatBytes")
    }
}

/// (String) -> String
internal struct StrToStrMap: LKMapMethod, StringReturn {
    static var callSignature:[LeafCallParameter] { [.string] }

    func evaluate(_ params: LeafCallValues) -> LKData { .string(f(params[0].string!)) }
    
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
    static var callSignature:[LeafCallParameter] {[
        .string, .string(labeled: "occurencesOf"), .string(labeled: "with")
    ]}
    
    func evaluate(_ params: LeafCallValues) -> LKData {
        .string(f(params[0].string!, params[1].string!, params[2].string!)) }
    
    private init(_ map: @escaping (String, String, String) -> String) { f = map }
    private let f: (String, String, String) -> String
    
    static let replace: Self = .init({ $0.replacingOccurrences(of: $1, with: $2) })
    
}

public struct DoubleFormatterMap: LKMapMethod, StringReturn {
    public static var callSignature: [LeafCallParameter] {[
        .double, .int(labeled: "places", defaultValue: Int(Self.defaultPlaces).leafData)
    ]}
    
    public static var invariant: Bool { true }
    
    public func evaluate(_ params: LeafCallValues) -> LeafData {
        .string(f(params[0].double!, params[1].int!))
    }
    
    @LeafRuntimeGuard public static var defaultPlaces: UInt8 = 2
    
    private init(_ map: @escaping (Double, Int) -> String) { f = map }
    private let f: (Double, Int) -> String
    
    static let seconds: Self = .init({$0.formatSeconds(places: Int($1))})
}

public struct IntFormatterMap: LKMapMethod, StringReturn {
    public static var callSignature: [LeafCallParameter] {[
        .int, .int(labeled: "places", defaultValue: Int(Self.defaultPlaces).leafData)
    ]}
    
    public static var invariant: Bool { true }
    
    public func evaluate(_ params: LeafCallValues) -> LeafData {
        .string(f(params[0].int!, params[1].int!))
    }
    
    @LeafRuntimeGuard public static var defaultPlaces: UInt8 = 2
    
    private init(_ map: @escaping (Int, Int) -> String) { f = map }
    private let f: (Int, Int) -> String
    
    static let bytes: Self = .init({$0.formatBytes(places: Int($1))})
}
