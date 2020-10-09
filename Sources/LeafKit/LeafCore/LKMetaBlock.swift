// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - LKMetaBlock

internal extension LeafEntities {
    func registerMetaBlocks() {
        use(RawSwitch.self , asMeta: "raw")
        use(Define.self    , asMeta: "define")
        use(Define.self    , asMeta: "def")
        use(Evaluate.self  , asMeta: "evaluate")
        use(Evaluate.self  , asMeta: "eval")
        use(Inline.self    , asMeta: "inline")
        
        
    }
}

internal protocol LKMetaBlock: LeafBlock { static var form: LKMetaForm { get } }

internal enum LKMetaForm: Int, Hashable {
    case rawSwitch
    case define
    case evaluate
    case inline
}

// MARK: - Define/Evaluate/Inline/RawSwitch

/// `Define` blocks will be followed by a normal scope table reference or an atomic syntax
internal struct Define: LKMetaBlock, EmptyParams, VoidReturn, Invariant {
    static var form: LKMetaForm { .define }

    var identifier: String
    var param: LKParameter?
    var table: Int
    var row: Int

    mutating func remap(offset: Int) { table += offset }
    
    static let warning = "call signature is (identifier) when a block, (identifier, evaluableParameter) when a function"
}

/// `Evaluate` blocks will be followed by either a nil scope syntax or a passthrough syntax if it has a defaulted value
internal struct Evaluate: LKMetaBlock, EmptyParams, AnyReturn {
    static var form: LKMetaForm { .evaluate }
    static var invariant: Bool { false }

    let identifier: String
    let defaultValue: LKParameter?

    static let warning = "call signature is (identifier) or (identifier ?? evaluableParameter)"
}

/// `Inline` is always followed by a rawBlock with the current rawHandler state, and a nil scope syntax if processing
///
/// When resolving, if processing, inlined template's AST will be appended to the AST, `Inline` block's +2
/// scope syntax will point to the inlined file's remapped entry table.
/// If inlined file is not being processed, rawBlock will be replaced with one of the same type with the inlined
/// raw document's contents.
internal struct Inline: LKMetaBlock, EmptyParams, VoidReturn, Invariant {
    static var form: LKMetaForm { .inline }

    var file: String
    var process: Bool
    var rawIdentifier: String?
    var availableVars: Set<LKVariable>?
}

/// `RawSwitch` either alters the current raw handler when by itself, or produces an isolated raw handling block with an attached scope
internal struct RawSwitch: LKMetaBlock, EmptyParams, AnyReturn, Invariant {
    static var form: LKMetaForm { .rawSwitch }

    init(_ factory: LKRawBlock.Type, _ tuple: LKTuple) {
        self.factory = factory
        self.params = .init(tuple.values.map {$0.data!} , tuple.labels)
    }

    var factory: LKRawBlock.Type
    var params: LeafCallValues
}

// MARK: Default Implementations

extension LKMetaBlock {
    static var parseSignatures: ParseSignatures? { __Unreachable("LKMetaBlock") }
    static var evaluable: Bool { false }
    
    var form: LKMetaForm { Self.form }
    var scopeVariables: [String]? { nil }
    
    static func instantiate(_ signature: String?,
                            _ params: [String]) throws -> Self  { __Unreachable("LKMetaBlock") }

    mutating func evaluateScope(_ params: LeafCallValues,
                                   _ variables: inout [String: LeafData]) -> EvalCount  { .once }
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> EvalCount {
        __Unreachable("Metablocks only called once") }
}

