internal extension LeafEntities {
    func registerDoubleReturns() {
        use(DoubleIntToDoubleMap.rounded, asMethod: "rounded")
    }
}

/// (Array || Dictionary.values) -> Int
internal struct DoubleIntToDoubleMap: LKMapMethod, DoubleReturn {
    static var callSignature: [LeafCallParameter] { [.double, .int(labeled: "places")] }

    func evaluate(_ params: LeafCallValues) -> LKData { .double(f(params[0].double!, params[1].int!))  }

    static let rounded: Self = .init({let x = pow(10, Double($1)); return ($0*x).rounded(.toNearestOrAwayFromZero)/x})
    
    private init(_ map: @escaping (Double, Int) -> Double) { f = map }
    private let f: (Double, Int) -> Double
}
