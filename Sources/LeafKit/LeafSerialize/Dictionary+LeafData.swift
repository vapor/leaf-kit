public extension Dictionary where Key == String, Value == LeafData {
    subscript(keyPath keyPath: String) -> LeafData? {
        let comps = keyPath.split(separator: ".").map(String.init)
        return self[keyPath: comps]
    }

    subscript(keyPath comps: [String]) -> LeafData? {
        if comps.isEmpty {
            return nil
        } else if comps.count == 1 {
            return self[comps[0]]
        }

        var comps = comps
        let key = comps.removeFirst()
        guard let val = self[key]?.dictionary else {
            return nil
        }
        return val[keyPath: comps]
    }
}
