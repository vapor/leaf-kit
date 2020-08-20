// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - LKMetaBlock

internal protocol LKMetaBlock: LeafBlock {
    static var form: LKMetaForm { get }
}

internal enum LKMetaForm: Int, Hashable {
    case rawSwitch
    case define
    case evaluate
    case inline
}

// MARK: - Define/Evaluate/Inline/RawSwitch

/// `Define` blocks will be followed by a normal scope table reference or an atomic syntax
internal struct Define: LKMetaBlock {
    static let form: LKMetaForm = .define
    static let callSignature: CallParameters = []
    static let returns: Set<LKDType> = [.void]
    static let invariant: Bool = true

    var identifier: String
    var param: LKParameter?
    var table: Int
    var row: Int

    mutating func remap(offset: Int) { table += offset }

    static let warning = "call signature is (identifier) when a block, (identifier, evaluableParameter) when a function"
}

/// `Evaluate` blocks will be followed by either a nil scope syntax or a passthrough syntax if it has a defaulted value
internal struct Evaluate: LKMetaBlock {
    static let form: LKMetaForm = .evaluate
    static let callSignature: CallParameters = []
    static let returns: Set<LKDType> = .any
    static let invariant: Bool = true

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
internal struct Inline: LKMetaBlock {
    init(_ file: String, process: Bool, rawIdentifier: String?) {
        self.file = file
        self.process = process
        self.rawIdentifier = rawIdentifier
    }

    static let form: LKMetaForm = .inline
    static let callSignature: CallParameters = []
    static let returns: Set<LKDType> = [.void]
    static let invariant: Bool = true

    var file: String
    var process: Bool
    var rawIdentifier: String?
}

/// `RawSwitch` either alters the current raw handler when by itself, or produces an isolated raw handling block with an attached scope
internal struct RawSwitch: LKMetaBlock {
    static let form: LKMetaForm = .rawSwitch
    static let callSignature: CallParameters = []
    static let returns: Set<LKDType> = .any
    static let invariant: Bool = true

    init(_ factory: LKRawBlock.Type, _ tuple: LKTuple) {
        self.factory = factory
        self.params = .init(tuple.values.map {$0.data!} , tuple.labels)
    }

    var factory: LKRawBlock.Type
    var params: CallValues
}

// MARK: Default Implementations

extension LKMetaBlock {
    static var parseSignatures: ParseSignatures? { __MajorBug("LKMetaBlock") }
    static var evaluable: Bool { false }
    static func instantiate(_ signature: String?, _ params: [String]) throws -> Self  {
        __MajorBug("LKMetaBlock") }

    var form: LKMetaForm { Self.form }

    var scopeVariables: [String]? { nil }
    mutating func evaluateScope(_ params: CallValues,
                                   _ variables: inout [String: LeafData]) -> EvalCount  { .once }
    mutating func reEvaluateScope(_ variables: inout [String: LeafData]) -> EvalCount {
        __MajorBug("Metablocks only called once") }
}
