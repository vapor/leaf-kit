// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Raw Handlers
import Foundation
import NIOFoundationCompat


public struct LeafBuffer: LKRawBlock {    
    @LeafRuntimeGuard public static var boolFormatter: (Bool) -> String = { $0.description }
    @LeafRuntimeGuard public static var intFormatter: (Int) -> String = { $0.description }
    @LeafRuntimeGuard public static var doubleFormatter: (Double) -> String = { $0.description }
    @LeafRuntimeGuard public static var nilFormatter: () -> String = { "" }
    @LeafRuntimeGuard public static var stringFormatter: (String) -> String = { $0 }
    @LeafRuntimeGuard public static var dataFormatter: (Data) -> String? =
        { String(data: $0, encoding: LKConf.encoding) }
    
    internal init(_ output: ByteBuffer, _ encoding: String.Encoding) {
        self.output = output
        self.encoding = encoding
    }
    
    private(set) var error: String? = nil
    private(set) var encoding: String.Encoding
    private var output: ByteBuffer
    
    static var recall: Bool { false }

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
                case .bool       : try write(Self.boolFormatter(data.bool!))
                case .data       : try write(Self.dataFormatter(data.data!) ?? "")
                case .double     : try write(Self.doubleFormatter(data.double!))
                case .int        : try write(Self.intFormatter(data.int!))
                case .string     : try write(Self.stringFormatter(data.string!))
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
    
    mutating func close() {}

    var byteCount: UInt32 { output.byteCount }
    var contents: String { output.contents }
        
    mutating func write(_ str: String) throws { try output.writeString(str, encoding: LKConf.encoding) }
}

extension ByteBuffer: LKRawBlock {
    var error: String? { nil }
    var encoding: String.Encoding { LKConf.encoding }
    
    static var recall: Bool { false }

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
            case .bool       : write(LeafBuffer.boolFormatter(data.bool!))
            case .data       : write(LeafBuffer.dataFormatter(data.data!) ?? "")
            case .double     : write(LeafBuffer.doubleFormatter(data.double!))
            case .int        : write(LeafBuffer.intFormatter(data.int!))
            case .string     : write(LeafBuffer.stringFormatter(data.string!))
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
    
    mutating func close() {}

    var byteCount: UInt32 { UInt32(readableBytes) }
    var contents: String { getString(at: readerIndex, length: readableBytes) ?? "" }
    
    mutating func write(_ str: String) { try! writeString(str, encoding: LKConf.encoding) }
}
