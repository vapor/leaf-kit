// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Raw Handlers

import NIOFoundationCompat

extension ByteBuffer: LKRawBlock {
    var error: String? {nil}
    var encoding: String.Encoding { LKConf.encoding }
    
    /// `ByteBuffer` never attempts to signal state and can be directly output
    static var stateful: Bool { false }
    static var recall: Bool { false }

    /// `ByteBuffer` is a naive pass-through handler of itself
    static func instantiate(data: ByteBuffer?,
                            encoding: String.Encoding) -> LKRawBlock {
        data ?? ByteBufferAllocator().buffer(capacity: 0) }

    static func instantiate(size: UInt32,
                            encoding: String.Encoding) -> LKRawBlock {
        ByteBufferAllocator().buffer(capacity: Int(size)) }


    /// Always identity return and valid
    var serialized: (buffer: ByteBuffer, valid: Bool?) { (self, true) }

    /// Always takes either the serialized view of a `LKRawBlock` or the direct result if it's a `ByteBuffer`
    mutating func append(_ block: inout LKRawBlock) {
        var input = block as? Self ?? block.serialized.buffer
        let inputEncoding = block.encoding
        
        guard encoding != inputEncoding else { writeBuffer(&input); return }
        fatalError()
    }

    /// Appends data using configured serializer views
    mutating func append(_ data: LeafData) {
        switch data.celf {
            case .bool       : write(LKConf.boolFormatter(data.bool!))
            case .data       : write(LKConf.dataFormatter(data.data!) ?? "")
            case .double     : write(LKConf.doubleFormatter(data.double!))
            case .int        : write(LKConf.intFormatter(data.int!))
            case .string     : write(LKConf.stringFormatter(data.string!))
            case .void       : break
            case .array      : let a = data.array!
                               write("[")
                               for index in a.indices {
                                    append(a[index])
                                    if index != a.indices.last! { write(", ") }
                               }
                               write("]")
            case .dictionary : let d = data.dictionary!.sorted { $0.key < $1.key }
                               write("[")
                               for index in d.indices {
                                    write("\"\(d[index].key)\": ")
                                    append(d[index].value)
                                    if index != d.indices.last! { write(", ") }
                               }
                               if d.isEmpty { write(":") }
                               write("]")
        }
    }

    var byteCount: UInt32 { UInt32(readableBytes) }
    var contents: String { getString(at: readerIndex, length: readableBytes) ?? "" }
    
    mutating func write(_ str: String) { try! writeString(str, encoding: LKConf.encoding) }
}


internal struct LKBuffer: LKRawBlock {
    internal init(_ output: ByteBuffer, _ encoding: String.Encoding) {
        self.output = output
        self.encoding = encoding
    }
    
    private(set) var error: String? = nil
    private(set) var encoding: String.Encoding
    private var output: ByteBuffer
    
    /// `ByteBuffer` never attempts to signal state and can be directly output
    static var stateful: Bool { false }
    static var recall: Bool { false }

    /// `ByteBuffer` is a naive pass-through handler of itself
    static func instantiate(data: ByteBuffer?,
                            encoding: String.Encoding) -> LKRawBlock {
        Self.init(data ?? ByteBufferAllocator().buffer(capacity: 0), encoding) }

    static func instantiate(size: UInt32,
                            encoding: String.Encoding) -> LKRawBlock {
        Self.init(ByteBufferAllocator().buffer(capacity: Int(size)), encoding) }


    /// Always identity return and valid
    var serialized: (buffer: ByteBuffer, valid: Bool?) { (output, true) }

    /// Always takes either the serialized view of a `LKRawBlock` or the direct result if it's a `ByteBuffer`
    mutating func append(_ block: inout LKRawBlock) {
        var input = (block as? Self)?.output ?? block.serialized.buffer
        guard encoding != block.encoding else { output.writeBuffer(&input); return }
        guard let x = input.readString(length: input.readableBytes,
                                       encoding: block.encoding) else {
            self.error = "Couldn't transcode input raw block"; return
        }
        do { try write(x) }
        catch { self.error = error.localizedDescription }
    }

    /// Appends data using configured serializer views
    mutating func append(_ data: LeafData) {
        do {
            switch data.celf {
                case .bool       : try write(LKConf.boolFormatter(data.bool!))
                case .data       : try write(LKConf.dataFormatter(data.data!) ?? "")
                case .double     : try write(LKConf.doubleFormatter(data.double!))
                case .int        : try write(LKConf.intFormatter(data.int!))
                case .string     : try write(LKConf.stringFormatter(data.string!))
                case .void       : break
                case .array      : let a = data.array!
                                   try write("[")
                                   for index in a.indices {
                                        append(a[index])
                                        if index != a.indices.last! { try write(", ") }
                                   }
                                   try write("]")
                case .dictionary : let d = data.dictionary!.sorted { $0.key < $1.key }
                                   try write("[")
                                   for index in d.indices {
                                        try write("\"\(d[index].key)\": ")
                                        append(d[index].value)
                                        if index != d.indices.last! { try write(", ") }
                                   }
                                   if d.isEmpty { try write(":") }
                                   try write("]")
            }
        } catch { self.error = error.localizedDescription }
    }

    var byteCount: UInt32 { output.byteCount }
    var contents: String { output.contents }
        
    mutating func write(_ str: String) throws { try output.writeString(str, encoding: LKConf.encoding) }
}
