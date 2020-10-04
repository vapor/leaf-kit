extension LeafEntities {
    func registerTypeCasts() {
        use(Double.self, asType: "Double", storeAs: .double)
        use(Int.self, asType: "Int", storeAs: .int)
        use(Bool.self, asType: "Bool", storeAs: .bool)
        use(String.self, asType: "String", storeAs: .string)
        use([LeafData].self, asType: "Array", storeAs: .array)
        use([String: LeafData].self, asType: "Dictionary", storeAs: .dictionary)
        
        /// See `LeafData`
        use(LKDSelfMethod(), asMethod: "type")
        use(LKDSelfFunction(), asFunction: "type")
    }
}

internal protocol TypeCast: LKMapMethod {}
internal extension TypeCast { func evaluate(_ params: LeafCallValues) -> LKData { params[0] } }

internal struct BoolIdentity: TypeCast, BoolReturn {
    static var callSignature: [LeafCallParameter] { [.bool] } }
internal struct IntIdentity: TypeCast, IntReturn {
    static var callSignature: [LeafCallParameter] { [.int] } }
internal struct DoubleIdentity: TypeCast, DoubleReturn {
    static var callSignature: [LeafCallParameter] { [.double] } }
internal struct StringIdentity: TypeCast, StringParam, StringReturn {}
internal struct ArrayIdentity: TypeCast, ArrayParam, ArrayReturn {}
internal struct DictionaryIdentity: TypeCast, DictionaryParam, DictionaryReturn {}

internal struct DataIdentity: TypeCast, DataReturn {
    static var callSignature: [LeafCallParameter] { [.data] }
}

