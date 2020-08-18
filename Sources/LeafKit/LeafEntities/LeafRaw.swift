// MARK: Subject to change prior to 1.0.0 release

/// A `RawBlock` is a specialized `LeafBlock` that is provided raw ByteBuffer input.
///
/// It may optionally process in another language and maintain its own state.
public protocol RawBlock: LeafFunction {
    /// If this raw handler is stateful
    /// - False if this handler makes no attempts to manage the state of its contents.
    /// - True if it should be signaled when the next raw block is the same type
    static var stateful: Bool { get }

    /// If the raw handler should be recalled after it has been provided its block's serialized contents
    static var recall: Bool { get }

    /// Generate a `.raw` block
    /// - Parameters:
    ///   - data: Raw ByteBuffer input, if any exists yet
    ///   - encoding: Encoding of the incoming string.
    static func instantiate(data: ByteBuffer?,
                            encoding: String.Encoding) -> RawBlock

    /// Generate a `.raw` block
    /// - Parameters:
    ///   - size: Expected minimum byte count required
    ///   - encoding: Encoding of the incoming string.
    static func instantiate(size: UInt32,
                            encoding: String.Encoding) -> RawBlock

    /// Adherent must be able to provide a serialized view of itself in entirety
    ///
    /// `valid` shall be semantic for the block type. An HTML raw block might report as follows
    /// ```
    /// <div></div>   // true (valid as an encapsulated block)
    /// <div><span>   // nil (indefinite)
    /// <div></span>  // false (always invalid)
    var serialized: (buffer: ByteBuffer, valid: Bool?) { get }

    /// Optional error information if the handler is stateful which LeafKit may choose to report/log.
    var error: String? { get }

    /// Append a second block to this one.
    ///
    /// If the second block is the same type, adherent should take care of maintaining state as necessary.
    /// If it isn't of the same type, adherent may assume it's a completed RawBlock and access
    /// `block.serialized` to obtain a `ByteBuffer` to append
    mutating func append(_ block: inout RawBlock) throws

    mutating func append(_ buffer: inout ByteBuffer) throws

    mutating func append(_ data: LeafData)

    /// Bytes in the raw buffer
    var byteCount: UInt32 { get }
    var contents: String { get }
}

/// Default implementations for typical `RawBlock`s
public extension RawBlock {
    /// Most `RawBlocks` won't have a parse signature
//    static var parseSignatures: [String: [ParseParameter]]? { nil }
    /// Most blocks are not evaluable
    static var returns: Set<LeafDataType> { [.void] }

    static var invariant: Bool { true }
    static var callSignature: CallParameters {[]}
//
//    var scopeVariables: [String]? { nil }
//
//    func evaluateScope(_ params: CallValues) -> ScopeValue { .once() }

    /// RawBlocks will never be called with evaluate
    func evaluate(_ params: CallValues) -> LeafData { .trueNil }
}

