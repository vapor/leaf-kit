

internal struct LKTuple: LKSymbol {
    // MARK: - Stored Properties
    
    var values: LKParams { didSet { setStates() } }
    var labels: [String: Int]
    
    // MARK: LKSymbol
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>
    
    // MARK: - Initializer
    init(_ tuple: [(label: String?, param: LKParameter)] = []) {
        self.values = []
        self.labels = [:]
        self.symbols = []
        self.resolved = false
        self.invariant = false
        for index in 0..<tuple.count {
            values.append(tuple[index].param)
            if let label = tuple[index].label { labels[label] = index }
        }
    }
    
    // MARK: - Computed Properties
    // MARK: LKPrintable
    /// `(_: value(1), isValid: bool(true), ...)`
    var description: String {
        let inverted = labels.map { ($0.value, $0.key) }
        var labeled: [String] = []
        for (index, value) in values.enumerated() {
            let label = inverted.first?.0 == index ? inverted.first!.1 : "_"
            labeled.append("\(label): \(value.description)")
        }
        return "(\(labeled.joined(separator: ", ")))"
    }
    
    /// `(value(1), bool(true), ...)`
    var short: String {
        "(\(values.map { $0.short }.joined(separator: ", ")))"
    }
    
    // MARK: LKSymbol
    func resolve(_ symbols: LKVarTable) -> Self { self }
    func evaluate(_ symbols: LKVarTable) -> LeafData { .trueNil }
    
    // MARK: Fake Collection Adherence
    var isEmpty: Bool { values.isEmpty }
    var count: Int { values.count }
    
    var enumerated: [(label: String?, value: LKParameter)] {
        let inverted = Dictionary(uniqueKeysWithValues: labels.map { ($0.value, $0.key) })
        return values.enumerated().map { (inverted[$0.offset], $0.element) }
    }
    
    subscript(index: String) -> LKParameter? {
        get { if let i = labels[index] { return i < count ? self[i] : nil }; return nil }
        set { if let i = labels[index], i < count { self[i] = newValue } }
    }
    
    subscript(index: Int) -> LKParameter? {
        get { (0..<count).contains(index) ? values[index] : nil }
        set { if (0..<count).contains(index) { values[index] = newValue! } }
    }
    
    mutating func append(_ more: Self) {
        values.append(contentsOf: more.values)
        more.labels.mapValues { $0 + self.count }.forEach { labels[$0.key] = $0.value }
    }
    
    // MARK: Private Only
    
    mutating private func setStates() {
        resolved = values.allSatisfy { $0.resolved }
        invariant = values.allSatisfy { $0.invariant }
        symbols = values.reduce(into: .init()) { $0.formUnion($1.symbols) }
    }
}
