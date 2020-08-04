// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Raw Handlers

/// Adherance for `ByteBuffer` to `RawBlock` as a factory for making raw blocks
extension ByteBuffer: RawBlock {
    /// `ByteBuffer` never attempts to signal state and can be directly output
    public static var stateful: Bool { false }
    public static var recall: Bool { false }

    /// `ByteBuffer` is a naive pass-through handler of itself
    public static func instantiate(data: ByteBuffer?,
                                   encoding: String.Encoding) -> RawBlock {
        data ?? ByteBufferAllocator().buffer(capacity: 0)
    }
    
    /// Never errors
    public var error: String? { nil }

    /// Always identity return and valid
    public var serialized: (buffer: ByteBuffer, valid: Bool?) { (self, true) }
    
    /// Always takes either the serialized view of a `RawBlock` or the direct result if it's a `ByteBuffer`
    mutating public func append(_ block: inout RawBlock) throws {
        var byteBuffer = block as? Self ?? block.serialized.buffer
        writeBuffer(&byteBuffer)
    }

    public mutating func append(_ buffer: inout ByteBuffer) throws {
        writeBuffer(&buffer)
    }
    
    // appends data using configured serializer views
    public mutating func append(_ data: LeafData) {
        let c = LeafConfiguration.self
        switch data.celf {
            case .bool       : writeString(c.boolFormatter(data.bool!))
            case .data       : writeString(c.dataFormatter(data.data!) ?? "")
            case .double     : writeString(c.doubleFormatter(data.double!))
            case .int        : writeString(c.intFormatter(data.int!))
            case .string     : writeString(c.stringFormatter(data.string!))
            case .void       : break
            case .array      : let a = data.array!
                               writeString("[")
                               a.forEach { append($0); writeString(", ") }
                               moveWriterIndex(to: writerIndex - 2)
                               writeString("]")
            case .dictionary : let d = data.dictionary!
                               writeString("[")
                               d.sorted { $0.key < $1.key }.forEach {
                                    writeString("\"\($0.key)\": ")
                                    append($0.value)
                                    writeString(", ")
                               }
                               moveWriterIndex(to: writerIndex - 2)
                               writeString("]")
        }
    }
    
    public var byteCount: UInt64 { UInt64(readableBytes) }
    public var contents: String { getString(at: readerIndex, length: readableBytes) ?? "" }
    
    internal static let newLine = instantiate(data: .init(string: "\n"), encoding: .utf8)
}
