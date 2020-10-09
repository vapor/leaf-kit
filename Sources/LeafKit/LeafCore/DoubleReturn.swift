internal extension LeafEntities {
    func registerDoubleReturns() {
        use(DoubleIntToDoubleMap.rounded, asMethod: "rounded")
   //     use(DoubleDoubleToDoubleMap._min, asFunction: "min")
   //     use(DoubleDoubleToDoubleMap._max, asFunction: "max")
    }
}

/// (Array || Dictionary.values) -> Int
internal struct DoubleIntToDoubleMap: LKMapMethod, DoubleReturn {
    static var callSignature: [LeafCallParameter] { [.double, .int(labeled: "places")] }

    func evaluate(_ params: LeafCallValues) -> LKData { .double(f(params[0].double!, params[1].int!)) }

    static let rounded: Self = .init({let x = pow(10, Double($1)); return ($0*x).rounded(.toNearestOrAwayFromZero)/x})
    
    private init(_ map: @escaping (Double, Int) -> Double) { f = map }
    private let f: (Double, Int) -> Double
}

internal struct DoubleDoubleToDoubleMap: LKMapMethod, DoubleReturn {
    static var callSignature: [LeafCallParameter] = [.double, .double]
    
    func evaluate(_ params: LeafCallValues) -> LKData { .double(f(params[0].double!, params[1].double!)) }
    
    static let _min: Self = .init({ min($0, $1) })
    static let _max: Self = .init({ max($0, $1) })
    
    private init(_ map: @escaping (Double, Double) -> Double) { f = map }
    private let f: (Double, Double) -> Double
}
