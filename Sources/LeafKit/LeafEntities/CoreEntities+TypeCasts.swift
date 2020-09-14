extension LeafEntities {
    func registerTypeCasts() {
        use(Double.self, asType: "Double", storeAs: .double)
        use(Int.self, asType: "Int", storeAs: .int)
        use(Bool.self, asType: "Bool", storeAs: .bool)
        use(String.self, asType: "String", storeAs: .string)
        use([LeafData].self, asType: "Array", storeAs: .array)
        use([String: LeafData].self, asType: "Dictionary", storeAs: .dictionary)
    }
}

internal protocol TypeCast: LKMapMethod {}
extension TypeCast {
    func evaluate(_ params: CallValues) -> LKData { params[0] }
}

struct IntIdentity: TypeCast, IntReturn {
    static let callSignature: CallParameters = [.int]
}

struct DoubleIdentity: TypeCast, DoubleReturn {
    static let callSignature: CallParameters = [.double]
}

struct BoolIdentity: TypeCast, BoolReturn {
    static let callSignature: CallParameters = [.bool]
}

struct StringIdentity: TypeCast, StringReturn {
    static let callSignature: CallParameters = [.string]
}

struct DataIdentity: TypeCast, DataReturn {
    static let callSignature: CallParameters = [.data]
}

struct ArrayIdentity: TypeCast, ArrayReturn {
    static let callSignature: CallParameters = [.array]
}

struct DictionaryIdentity: TypeCast, DictionaryReturn {
    static let callSignature: CallParameters = [.dictionary]
}
