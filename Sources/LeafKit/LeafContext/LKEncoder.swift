import Foundation

internal class LKEncoder: LeafDataRepresentable, Encoder {
    init(_ codingPath: [CodingKey] = [], _ softFail: Bool = true) {
        self.codingPath = codingPath
        self.softFail = softFail
        self.root = nil
    }
    
    var codingPath: [CodingKey]
    
    let softFail: Bool
    var leafData: LeafData { root?.leafData ?? err }
    var err: LeafData { softFail ? .trueNil : .error("No Encodable Data", function: "LKEncoder") }
    
    var root: LKEncoder?
    
    func container<K>(keyedBy type: K.Type) -> KeyedEncodingContainer<K> where K : CodingKey {
        root = LKEncoderKeyed<K>(codingPath, softFail)
        return .init(root as! LKEncoderKeyed<K>)
    }
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        root = LKEncoderUnkeyed(codingPath, softFail)
        return root as! LKEncoderUnkeyed
    }
    func singleValueContainer() -> SingleValueEncodingContainer {
        root = LKEncoderAtomic(codingPath, softFail)
        return root as! LKEncoderAtomic
    }
    
    /// Ignored
    var userInfo: [CodingUserInfoKey : Any] {[:]}
    
    @inline(__always)
    func _encode<T>(_ value: T) throws -> LeafData where T: Encodable {
        if let v = value as? LeafDataRepresentable { return state(v.leafData) }
        let e = LKEncoder(codingPath, softFail)
        try value.encode(to: e)
        return state(e.leafData)
    }
    
    @inline(__always)
    func state(_ value: LeafData) -> LeafData { value.errored && softFail ? .trueNil : value }
}

internal final class LKEncoderAtomic: LKEncoder, SingleValueEncodingContainer {
    lazy var container: LeafData = err
    override var leafData: LeafData { container }
    
    func encodeNil() throws { container = .trueNil }
    func encode<T>(_ value: T) throws where T: Encodable { container = try _encode(value) }
}

internal final class LKEncoderUnkeyed: LKEncoder, UnkeyedEncodingContainer {
    var array: [LeafDataRepresentable] = []
    var count: Int { array.count }
    
    override var leafData: LeafData { .array(array.map {$0.leafData}) }
    
    func encodeNil() throws { array.append(LeafData.trueNil) }
    func encode<T>(_ value: T) throws where T : Encodable { try array.append(_encode(value)) }
    
    func nestedContainer<K>(keyedBy keyType: K.Type) -> KeyedEncodingContainer<K> where K: CodingKey {
        let c = LKEncoderKeyed<K>(codingPath, softFail)
        array.append(c)
        return .init(c)
    }
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let c = LKEncoderUnkeyed(codingPath, softFail)
        array.append(c)
        return c
    }
    
    func superEncoder() -> Encoder { fatalError() }
}

internal final class LKEncoderKeyed<K>: LKEncoder,
                                        KeyedEncodingContainerProtocol where K: CodingKey {
    var dictionary: [String: LeafDataRepresentable] = [:]
    var count: Int { dictionary.count }
    
    override var leafData: LeafData { .dictionary(dictionary.mapValues {$0.leafData}) }
    
    func encodeNil(forKey key: K) throws { dictionary[key.stringValue] = LeafData.trueNil }
    func encodeIfPresent<T>(_ value: T?, forKey key: K) throws where T : Encodable {
        dictionary[key.stringValue] = try value.map { try _encode($0) } }
    func encode<T>(_ value: T, forKey key: K) throws where T : Encodable {
        dictionary[key.stringValue] = try _encode(value) }
    
    func nestedContainer<NK>(keyedBy keyType: NK.Type, forKey key: K) -> KeyedEncodingContainer<NK> where NK: CodingKey {
        let c = LKEncoderKeyed<NK>(codingPath, softFail)
        dictionary[key.stringValue] = c
        return .init(c)
    }
    func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        let c = LKEncoderUnkeyed(codingPath, softFail)
        dictionary[key.stringValue] = c
        return c
    }
    
    func superEncoder() -> Encoder { fatalError() }
    func superEncoder(forKey key: K) -> Encoder { fatalError() }
}
