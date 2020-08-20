// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Raw Handlers

/// Adherance for `ByteBuffer` to `LKRawBlock` as a factory for making raw blocks
extension ByteBuffer: LKRawBlock {
    /// `ByteBuffer` never attempts to signal state and can be directly output
    static var stateful: Bool { false }
    static var recall: Bool { false }

    /// `ByteBuffer` is a naive pass-through handler of itself
    static func instantiate(data: ByteBuffer?,
                                   encoding: String.Encoding) -> LKRawBlock {
        data ?? ByteBufferAllocator().buffer(capacity: 0)

    }

    static func instantiate(size: UInt32,
                                   encoding: String.Encoding) -> LKRawBlock {
        ByteBufferAllocator().buffer(capacity: Int(size))
    }

    /// Never errors
    var error: String? { nil }

    /// Always identity return and valid
    var serialized: (buffer: ByteBuffer, valid: Bool?) { (self, true) }

    /// Always takes either the serialized view of a `LKRawBlock` or the direct result if it's a `ByteBuffer`
    mutating func append(_ block: inout LKRawBlock) throws {
        var byteBuffer = block as? Self ?? block.serialized.buffer
        writeBuffer(&byteBuffer)
    }

    mutating func append(_ buffer: inout ByteBuffer) throws { writeBuffer(&buffer) }

    // appends data using configured serializer views
    mutating func append(_ data: LeafData) {
        switch data.celf {
            case .bool       : writeString(LKConf._boolFormatter(data.bool!))
            case .data       : writeString(LKConf._dataFormatter(data.data!) ?? "")
            case .double     : writeString(LKConf._doubleFormatter(data.double!))
            case .int        : writeString(LKConf._intFormatter(data.int!))
            case .string     : writeString(LKConf._stringFormatter(data.string!))
            case .void       : break
            case .array      : let a = data.array!
                               writeString("[")
                               a.forEach { append($0); writeString(", ") }
                               if !a.isEmpty { moveWriterIndex(to: writerIndex - 2) }
                               writeString("]")
            case .dictionary : let d = data.dictionary!
                               writeString("[")
                               d.sorted { $0.key < $1.key }.forEach {
                                    writeString("\"\($0.key)\": ")
                                    append($0.value)
                                    writeString(", ")
                               }
                               if !d.isEmpty { moveWriterIndex(to: writerIndex - 2) }
                               else { writeString(":") }
                               writeString("]")
        }
    }

    var byteCount: UInt32 { UInt32(readableBytes) }
    var contents: String { getString(at: readerIndex, length: readableBytes) ?? "" }

    static let newLine = instantiate(data: .init(string: "\n"), encoding: .utf8)
}
