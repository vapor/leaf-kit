public extension Encodable {
    func encodeToLeafData() -> LeafData {
        let encoder = LKEncoder()
        do { try encode(to: encoder) }
        catch { return .error(internal: "Could not encode \(String(describing: self)) to `LeafData`)") }
        return encoder.leafData
    }
}
