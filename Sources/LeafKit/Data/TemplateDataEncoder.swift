// TODO: - Should this be reimplemented? This let Leaf3 use Futures as data types?

///// Converts `Encodable` objects to `LeafData`.
//public final class LeafDataEncoder {
//    /// Create a new `LeafDataEncoder`.
//    public init() {}
//
//    /// Encode an `Encodable` item to `LeafData`.
//    public func encode<E>(_ encodable: E, on worker: Worker) throws -> Future<LeafData> where E: Encodable {
//        let encoder = _LeafDataEncoder(context: .init(data: .dictionary([:]), on: worker))
//        try encodable.encode(to: encoder)
//        return encoder.context.data.resolve(on: worker)
//    }
//}
//
///// MARK: Private
//
///// A reference wrapper around `LeafData`.
//fileprivate final class PartialLeafDataContext {
//    /// The referenced `LeafData`
//    public var data: PartialLeafData
//
//    let eventLoop: EventLoop
//
//    /// Create a new `LeafDataContext`.
//    public init(data: PartialLeafData, on worker: Worker) {
//        self.data = data
//        self.eventLoop = worker.eventLoop
//    }
//}
//
///// Holds partially evaluated template data. This may still contain futures
///// that need to be resolved.
//fileprivate enum PartialLeafData: NestedData {
//    case data(LeafData)
//    case future(Future<LeafData>)
//    case arr([PartialLeafData])
//    case dict([String: PartialLeafData])
//
//    func resolve(on worker: Worker) -> Future<LeafData> {
//        switch self {
//        case .data(let data): return Future.map(on: worker) { data }
//        case .future(let fut): return fut
//        case .arr(let arr):
//            return arr.map { $0.resolve(on: worker) }
//                .flatten(on: worker)
//                .map(to: LeafData.self) { return .array($0) }
//        case .dict(let dict):
//            return dict.map { (key, val) in
//                return val.resolve(on: worker).map(to: (String, LeafData).self) { val in
//                    return (key, val)
//                }
//            }.flatten(on: worker).map(to: LeafData.self) { arr in
//                var dict: [String: LeafData] = [:]
//                for (key, val) in arr {
//                    dict[key] = val
//                }
//                return .dictionary(dict)
//            }
//        }
//    }
//
//    // MARK: NestedData
//
//    /// See `NestedData`.
//    static func dictionary(_ value: [String: PartialLeafData]) -> PartialLeafData {
//        return .dict(value)
//    }
//
//    /// See `NestedData`.
//    static func array(_ value: [PartialLeafData]) -> PartialLeafData {
//        return .arr(value)
//    }
//
//    /// See `NestedData`.
//    var dictionary: [String: PartialLeafData]? {
//        switch self {
//        case .dict(let d): return d
//        default: return nil
//        }
//    }
//
//    /// See `NestedData`.
//    var array: [PartialLeafData]? {
//        switch self {
//        case .arr(let a): return a
//        default: return nil
//        }
//    }
//}
//
//fileprivate final class _LeafDataEncoder: Encoder, FutureEncoder {
//    var codingPath: [CodingKey]
//    var context: PartialLeafDataContext
//    var userInfo: [CodingUserInfoKey: Any] {
//        return [:]
//    }
//
//    init(context: PartialLeafDataContext, codingPath: [CodingKey] = []) {
//        self.context = context
//        self.codingPath = codingPath
//    }
//
//    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
//        let keyed = _LeafDataKeyedEncoder<Key>(codingPath: codingPath, context: context)
//        return KeyedEncodingContainer(keyed)
//    }
//
//    func unkeyedContainer() -> UnkeyedEncodingContainer {
//        return _LeafDataUnkeyedEncoder(codingPath: codingPath, context: context)
//    }
//
//    func singleValueContainer() -> SingleValueEncodingContainer {
//        return _LeafDataSingleValueEncoder(codingPath: codingPath, context: context)
//    }
//
//    func encodeFuture<E>(_ future: EventLoopFuture<E>) throws where E : Encodable {
//        let future = future.flatMap(to: LeafData.self) { encodable in
//            return try LeafDataEncoder().encode(encodable, on: self.context.eventLoop)
//        }
//        context.data.set(to: .future(future), at: codingPath)
//    }
//}
//
//fileprivate final class _LeafDataSingleValueEncoder: SingleValueEncodingContainer {
//    var codingPath: [CodingKey]
//    var context: PartialLeafDataContext
//
//    init(codingPath: [CodingKey], context: PartialLeafDataContext) {
//        self.codingPath = codingPath
//        self.context = context
//    }
//
//    func encodeNil() throws {
//        context.data.set(to: .data(.null), at: codingPath)
//    }
//
//    func encode<T>(_ value: T) throws where T: Encodable {
//        guard let data = value as? LeafDataRepresentable else {
//            throw TemplateKitError(identifier: "templateData", reason: "`\(T.self)` does not conform to `LeafDataRepresentable`.")
//        }
//        try context.data.set(to: .data(data.convertToLeafData()), at: codingPath)
//    }
//}
//
//fileprivate final class _LeafDataKeyedEncoder<K>: KeyedEncodingContainerProtocol where K: CodingKey {
//    typealias Key = K
//
//    var codingPath: [CodingKey]
//    var context: PartialLeafDataContext
//
//    init(codingPath: [CodingKey], context: PartialLeafDataContext) {
//        self.codingPath = codingPath
//        self.context = context
//    }
//
//    func superEncoder() -> Encoder {
//        return _LeafDataEncoder(context: context, codingPath: codingPath)
//    }
//
//    func encodeNil(forKey key: K) throws {
//        context.data.set(to: .data(.null), at: codingPath + [key])
//    }
//
//    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey>
//        where NestedKey : CodingKey
//    {
//        let container = _LeafDataKeyedEncoder<NestedKey>(codingPath: codingPath + [key], context: context)
//        return KeyedEncodingContainer(container)
//    }
//
//    func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
//        return _LeafDataUnkeyedEncoder(codingPath: codingPath + [key], context: context)
//    }
//
//    func superEncoder(forKey key: K) -> Encoder {
//        return _LeafDataEncoder(context: context, codingPath: codingPath + [key])
//    }
//
//    func encode<T>(_ value: T, forKey key: K) throws where T: Encodable {
//        if let data = value as? LeafDataRepresentable {
//            try context.data.set(to: .data(data.convertToLeafData()), at: codingPath + [key])
//        } else {
//
//            let encoder = _LeafDataEncoder(context: context, codingPath: codingPath + [key])
//            try value.encode(to: encoder)
//        }
//    }
//}
//
//
//fileprivate final class _LeafDataUnkeyedEncoder: UnkeyedEncodingContainer {
//    var count: Int
//    var codingPath: [CodingKey]
//    var context: PartialLeafDataContext
//
//    var index: CodingKey {
//        defer { count += 1 }
//        return BasicKey(count)
//    }
//
//    init(codingPath: [CodingKey], context: PartialLeafDataContext) {
//        self.codingPath = codingPath
//        self.context = context
//        self.count = 0
//        context.data.set(to: .array([]), at: codingPath)
//    }
//
//    func encodeNil() throws {
//        context.data.set(to: .data(.null), at: codingPath + [index])
//    }
//
//    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey>
//        where NestedKey: CodingKey
//    {
//        let container = _LeafDataKeyedEncoder<NestedKey>(codingPath: codingPath + [index], context: context)
//        return KeyedEncodingContainer(container)
//    }
//
//    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
//        return _LeafDataUnkeyedEncoder(codingPath: codingPath + [index], context: context)
//    }
//
//    func superEncoder() -> Encoder {
//        return _LeafDataEncoder(context: context, codingPath: codingPath + [index])
//    }
//
//    func encode<T>(_ value: T) throws where T: Encodable {
//        let encoder = _LeafDataEncoder(context: context, codingPath: codingPath + [index])
//        try value.encode(to: encoder)
//    }
//}
