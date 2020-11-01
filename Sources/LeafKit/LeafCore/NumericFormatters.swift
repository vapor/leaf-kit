public struct DoubleFormatterMap: LKMapMethod, StringReturn {
    @LeafRuntimeGuard public static var defaultPlaces: UInt8 = 2
    
    public static var callSignature: [LeafCallParameter] {[
        .double, .int(labeled: "places", defaultValue: Int(Self.defaultPlaces).leafData)
    ]}
        
    public func evaluate(_ params: LeafCallValues) -> LeafData {
        .string(f(params[0].double!, params[1].int!))  }
    
    static let seconds: Self = .init({$0.formatSeconds(places: Int($1))})
    
    private init(_ map: @escaping (Double, Int) -> String) { f = map }
    private let f: (Double, Int) -> String
}

public struct IntFormatterMap: LKMapMethod, StringReturn {
    @LeafRuntimeGuard public static var defaultPlaces: UInt8 = 2
    
    public static var callSignature: [LeafCallParameter] {[
        .int, .int(labeled: "places", defaultValue: Int(Self.defaultPlaces).leafData)
    ]}
        
    public func evaluate(_ params: LeafCallValues) -> LeafData {
        .string(f(params[0].int!, params[1].int!)) }
    
    internal static let bytes: Self = .init({$0.formatBytes(places: Int($1))})
    
    private init(_ map: @escaping (Int, Int) -> String) { f = map }
    private let f: (Int, Int) -> String
}
