public struct LeafSource {
    public let buffer: ByteBuffer
    public let length: Int
    
    static func start(at buffer: ByteBuffer) -> PartialLeafSource {
        return .init(buffer: buffer)
    }
}

struct PartialLeafSource {
    let buffer: ByteBuffer
    
    func end(at buffer: ByteBuffer) -> LeafSource {
        return LeafSource(buffer: self.buffer, length: self.buffer.readableBytes - buffer.readableBytes)
    }
}

public struct LeafError: Error, CustomStringConvertible {
    public enum Reason {
        case unexpectedToken
        case unterminatedStringLiteral
    }
    
    public let reason: Reason
    public let source: LeafSource?
    public var description: String {
        var desc: [String] = []
        desc.append("leaf error: \(self.reason)")
        if let source = self.source {
            let start = source.buffer.previousNewlineIndex ?? 0
            let offset = source.buffer.readerIndex - start
            let end = source.buffer.nextNewlineIndex ?? source.buffer.readerIndex
            let string = source.buffer.getString(
                at: start,
                length: end - start
            )
            desc.append(string ?? "n/a")
            var pointer = ""
            pointer += String(repeating: " ", count: offset - 1)
            pointer += "^"
            pointer += String(repeating: "~", count: source.length)
            desc.append(pointer)
        }
        return desc.joined(separator: "\n")
    }
    
    public init(_ reason: Reason, source: LeafSource? = nil) {
        self.reason = reason
        self.source = source
    }
}

extension ByteBuffer {
    var previousNewlineIndex: Int? {
        var i = self.readerIndex
        while let check = self.getInteger(at: i, as: UInt8.self) {
            if check == .newLine {
                return i
            }
            i -= 1
        }
        return nil
    }
    
    var nextNewlineIndex: Int? {
        var i = self.readerIndex
        while let check = self.getInteger(at: i, as: UInt8.self) {
            if check == .newLine {
                return i
            }
            i += 1
        }
        return nil
    }
}

import Foundation

extension LeafError: LocalizedError {
    public var errorDescription: String? {
        return self.description
    }
}
