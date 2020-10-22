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
    @LeafRuntimeGuard public static var nilFormatter: (_ type: String) -> String = { _ in "" }
    @LeafRuntimeGuard public static var stringFormatter: (String) -> String = { $0 }
    @LeafRuntimeGuard public static var dataFormatter: (Data, String.Encoding) -> String? =
        { String(data: $0, encoding: $1) }
    
    private(set) var error: Error? = nil
    private(set) var encoding: String.Encoding
    private var output: ByteBuffer
    
    /// Strip leading blank lines in appended raw blocks (for cropping after `voidAction()`)
    private var stripLeadingBlanklines: Bool = false
    /// Index of last trailing blank line of raw (for cropping extra whitespace at `close()`)
    private var trailingBlanklineIndex: Int? = nil
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
        close()
        var input = (block as? Self)?.output ?? block.serialized.buffer
//        guard encoding != block.encoding || stripBlanklines else {
//            output.writeBuffer(&input)
//            return
//        }
                
        guard var x = input.readString(length: input.readableBytes,
                                       encoding: block.encoding) else {
            self.error = "Couldn't transcode input raw block"; return
        }
        
        if stripLeadingBlanklines {
            while let nonWhitespace = x.firstIndex(where: {!$0.isWhitespace}),
                  let newline = x.firstIndex(where: {$0.isNewline}),
                  newline < nonWhitespace {
                x.removeSubrange(x.startIndex...newline)
                stripLeadingBlanklines = false
            }
            if x.firstIndex(where: {!$0.isWhitespace}) == nil,
               let newline = x.firstIndex(where: {$0.isNewline}) {
                x.removeSubrange(x.startIndex...newline) }
        }
        
        guard !x.isEmpty else { return }
        
        var cropped = ""
        
        if let lastNonWhitespace = x.lastIndex(where: {!$0.isWhitespace}),
           let lastNewline = x[lastNonWhitespace..<x.endIndex].lastIndex(where: {$0 == .newLine}),
           let cropIndex = x.index(after: lastNewline) as String.Index?,
           cropIndex < x.endIndex {
            cropped = String(x[cropIndex..<x.endIndex])
            x.removeSubrange(cropIndex..<x.endIndex)
        }
              
        do { try write(x) }
        catch { self.error = error }
        
        trailingBlanklineIndex = cropped.isEmpty ? nil : output.writerIndex
        if cropped.isEmpty { return }
        
        do { try write(cropped) }
        catch { self.error = error }
    }

    /// Appends data using configured serializer views
    mutating func append(_ data: LeafData) { _append(data) }
    
    /// Appends data using configured serializer views
    mutating func _append(_ data: LeafData, wrapString: Bool = false) {
        trailingBlanklineIndex = nil
        stripLeadingBlanklines = false
        do {
            guard !data.isNil else {
                try write(Self.nilFormatter(data.celf.short))
                return
            }
            switch data.celf {
                case .bool       : try write(Self.boolFormatter(data.bool!))
                case .data       : try write(Self.dataFormatter(data.data!, encoding) ?? "")
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
        } catch { self.error = error }
    }
    
    mutating func voidAction() {
        stripLeadingBlanklines = true
        close()
    }
    
    mutating func close() {
        if let newLine = trailingBlanklineIndex {
            trailingBlanklineIndex = nil
            output.moveWriterIndex(to: newLine)
        }
    }

    var byteCount: UInt32 { UInt32(output.readableBytes) }
    var contents: String {
        output.getString(at: 0,
                         length: trailingBlanklineIndex ?? output.readableBytes)
               ?? "" }
            
    mutating func write(_ str: String) throws {
        if (try? output.writeString(str, encoding: encoding)) == nil {
            throw err("`\(str)` is not encodable to `\(encoding.description)`")
        }
    }
}
