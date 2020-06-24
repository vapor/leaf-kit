// MARK: Subject to change prior to 1.0.0 release
// MARK: -

// TODO: Make `LeafSource` return this instead of `ByteBuffer` via extension
internal struct LeafRawTemplate {
    
    // MARK: - Internal Only
    
    let name: String
    
    init(name: String, src: String) {
        self.name = name
        self.body = .init(src)
    }

    mutating func readWhile(_ check: (Character) -> Bool) -> String {
        return String(readSliceWhile(pop: true, check))
    }

    mutating func peekWhile(_ check: (Character) -> Bool) -> String {
        return String(peekSliceWhile(check))
    }
    
    @discardableResult
    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        return readSliceWhile(pop: true, check).count
    }

    func peek(aheadBy idx: Int = 0) -> Character? {
        guard idx < body.count else { return nil }
        return body[idx]
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard !body.isEmpty else { return nil }
        let popped = body.removeFirst()
        switch popped {
            case .newLine:
                line += 1
                column = 0
            default:
                column += 1
        }
        return popped
    }
    
    // MARK: - Private Only
    
    private(set) var line = 0
    private(set) var column = 0

    private var body: [Character]
    
    private mutating func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        while let next = peek() {
            guard check(next) else { return str }
            if pop { self.pop() }
            str.append(next)
        }
        return str
    }

    private mutating func peekSliceWhile(_ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        var index = 0
        while let next = peek(aheadBy: index) {
            guard check(next) else { return str }
            str.append(next)
            index += 1
        }
        return str
    }
}
