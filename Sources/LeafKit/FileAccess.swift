import Foundation
import NIO

protocol FileAccessProtocol {
    func load(name: String) throws -> ByteBuffer
    func fload(name: String) throws -> EventLoopFuture<ByteBuffer>
}

// TODO: Take things like view directory
final class FileAccessor: FileAccessProtocol {
    func fload(name: String) throws -> EventLoopFuture<ByteBuffer> {
        fatalError()
    }
    
    func load(name: String) throws -> ByteBuffer {
        // todo: support things like view directory
        guard let data = FileManager.default.contents(atPath: name) else { throw "no document found at path \(name)" }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(data)
        return buffer
    }
}
