// TODO: Make `LeafSource` return this instead of `ByteBuffer` via extension
internal struct LeafRawTemplate {
    // MARK: - Internal Only
    let name: String
    
    init(name: String, src: String) {
        self.name = name
        self.body = src
        self.current = body.startIndex
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
        let peekIndex = body.index(current, offsetBy: idx)
        guard peekIndex < body.endIndex else { return nil }
        return body[peekIndex]
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard current < body.endIndex else { return nil }
        if body[current] == .newLine { line += 1; column = 0 }
        else { column += 1 }
        defer { current = body.index(after: current) }
        return body[current]
    }
    
    // MARK: - Private Only
    
    private(set) var line = 0
    private(set) var column = 0

    private let body: String
    private var current: String.Index
    
    mutating private func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        while let next = peek() {
            guard check(next) else { return str }
            if pop { self.pop() }
            str.append(next)
        }
        return str
    }

    mutating private func peekSliceWhile(_ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        var index = 0
        while let next = peek(aheadBy: index) {
            guard check(next) else { return str }
            str.append(next)
            index += 1
        }
        return str
    }
}
