internal extension LeafEntities {
    func registerErroring() {
        use(LDErrorIdentity(), asFunction: "Error")
        use(LDThrow(), asFunction: "throw")
    }
}

internal protocol LDError: Invariant, VoidReturn {}
extension LDError {
    func evaluate(_ params: LeafCallValues) -> LKData {
        .error(params[0].string!, function: String(describing: self)) }
}

internal struct LDErrorIdentity: LDError {
    static var callSignature: [LeafCallParameter] {
        [.init(types: .string, defaultValue: .string("Unknown serialize error"))] }    
}

internal struct LDThrow: LDError {
    static var callSignature: [LeafCallParameter] {
        [.string(labeled: "reason", defaultValue: .string("Unknown serialize error"))] }
}
