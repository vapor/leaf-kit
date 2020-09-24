internal extension LeafEntities {
    func registerDoubleReturns() {
        use(DoubleIntToDoubleMap.rounded, asMethod: "rounded")
    }
}

/// (Array || Dictionary.values) -> Int
internal struct DoubleIntToDoubleMap: LKMapMethod, DoubleReturn {
    static let callSignature:[LeafCallParameter] = [.double, .int(labeled: "places")]

    init(_ map: @escaping (Double, Int) -> Double) { f = map }

    func evaluate(_ params: LeafCallValues) -> LKData { .double(f(params[0].double!, params[1].int!))  }
    
    private let f: (Double, Int) -> Double

    static let rounded: Self = .init({let x = pow(10, Double($1)); return ($0*x).rounded(.toNearestOrAwayFromZero)/x})
}
