// MARK: Subject to change prior to 1.0.0 release
//

// MARK: - Raw Handlers
import Foundation
import NIOFoundationCompat

/// The default output object used by LeafKit to stream serialized data to.
public struct LeafBuffer {
    @LeafRuntimeGuard public static var boolFormatter: (Bool) -> String = { $0.description }
    @LeafRuntimeGuard public static var intFormatter: (Int) -> String = { $0.description }
    @LeafRuntimeGuard public static var doubleFormatter: (Double) -> String = { $0.description }
    @LeafRuntimeGuard public static var nilFormatter: () -> String = { "" }
    @LeafRuntimeGuard public static var stringFormatter: (String) -> String = { $0 }
    @LeafRuntimeGuard public static var dataFormatter: (Data) -> String? =
        { String(data: $0, encoding: LKConf.encoding) }
    
    private(set) var error: String? = nil
    private(set) var encoding: String.Encoding
    private var output: ByteBuffer
}

extension LeafBuffer: LKRawBlock {
    init(_ output: ByteBuffer, _ encoding: String.Encoding) {
        self.output = output
        self.encoding = encoding
    }
    
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
    mutating func append(_ data: LeafData) { _append(data) }
    
    /// Appends data using configured serializer views
    mutating func _append(_ data: LeafData, wrapString: Bool = false) {
        do {
            switch data.celf {
                case .bool       : try write(Self.boolFormatter(data.bool!))
                case .data       : try write(Self.dataFormatter(data.data!) ?? "")
                case .double     : try write(Self.doubleFormatter(data.double!))
                case .int        : try write(Self.intFormatter(data.int!))
                case .string     : try write(Self.stringFormatter(wrapString ? "\"\(data.string!)\""
                                                                             : data.string!))
                case .void       : break
                case .array      : let a = data.array!
                                   try write("[")
                                   for index in a.indices {
                                        _append(a[index], wrapString: true)
                                        if index != a.indices.last! { try write(", ") }
                                   }
                                   try write("]")
                case .dictionary : let d = data.dictionary!.sorted { $0.key < $1.key }
                                   try write("[")
                                   for index in d.indices {
                                        try write("\"\(d[index].key)\": ")
                                        _append(d[index].value, wrapString: true)
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
