// MARK: Subject to change prior to 1.0.0 release

/// A `LKRawBlock` is a specialized `LeafBlock` that is provided raw ByteBuffer input.
///
/// It may optionally process in another language and maintain its own state.
internal protocol LKRawBlock: LeafFunction {
    /// If the raw handler should be recalled after it has been provided its block's serialized contents
    static var recall: Bool { get }

    /// Generate a `.raw` block
    /// - Parameters:
    ///   - size: Expected minimum byte count required
    ///   - encoding: Encoding of the incoming string.
    static func instantiate(size: UInt32,
                            encoding: String.Encoding) -> LKRawBlock

    /// Adherent must be able to provide a serialized view of itself in entirety while open or closed
    ///
    /// `valid` shall be semantic for the block type. An HTML raw block might report as follows
    /// ```
    /// <div></div>   // true (valid as an encapsulated block)
    /// <div><span>   // nil (indefinite)
    /// <div></span>  // false (always invalid)
    var serialized: (buffer: ByteBuffer, valid: Bool?) { get }

    /// Optional error information if the handler is stateful which LeafKit may choose to report/log.
    var error: String? { get }
    
    var encoding: String.Encoding { get }

    /// Append a second block to this one.
    ///
    /// If the second block is the same type, adherent should take care of maintaining state as necessary.
    /// If it isn't of the same type, adherent may assume it's a completed LKRawBlock and access
    /// `block.serialized` to obtain a `ByteBuffer` to append
    mutating func append(_ block: inout LKRawBlock)

    mutating func append(_ data: LeafData)
    
    /// If type is `recall == true`, will be called when the block's scope is closed to allow cleanup/additions/validation
    mutating func close()

    /// Bytes in the raw buffer
    var byteCount: UInt32 { get }
    var contents: String { get }
}

/// Default implementations for typical `LKRawBlock`s
extension LKRawBlock {
    /// Most blocks are not evaluable
    public static var returns: Set<LeafDataType> { .void }

    public static var invariant: Bool { true }
    public static var callSignature:[LeafCallParameter] { [] }

    /// RawBlocks will never be called with evaluate
    public func evaluate(_ params: LeafCallValues) -> LeafData { .error(internal: "LKRawBlock called as function") }
    var recall: Bool { Self.recall }
}

