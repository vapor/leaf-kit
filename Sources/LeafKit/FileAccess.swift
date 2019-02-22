import Foundation

protocol FileAccessProtocol {
    func load(name: String) throws -> ByteBuffer
}

// TODO: Take things like view directory
final class FileAccessor: FileAccessProtocol {
    func load(name: String) throws -> ByteBuffer {
        // todo: support things like view directory
        guard let data = FileManager.default.contents(atPath: name) else { throw "no document found at path \(name)" }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(data)
        return buffer
    }
}
