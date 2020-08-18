// MARK: Subject to change prior to 1.0.0 release
// MARK: -

// FIXME: Should really be initializable directly from `ByteBuffer`
// TODO: Make `LeafSource` return this instead of `ByteBuffer` via extension
internal struct LKRawTemplate{
    // MARK: - Internal Only
    let name: String

    init(_ name: String, _ source: String) {
        self.name = name
        self.body = source
        self.current = body.startIndex
    }

    mutating func readWhile(_ check: (Character) -> Bool) -> String {
        readSliceWhile(pop: true, check)
    }

    @discardableResult
    mutating func readWhileNot(_ check: Set<Character>) -> String {
        readSliceWhile(pop: true, { !check.contains($0) })
    }

    mutating func peekWhile(_ check: (Character) -> Bool) -> String {
        peekSliceWhile(check)
    }

    @discardableResult
    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        readSliceWhile(pop: true, check).count
    }

    func peek(aheadBy idx: Int = 0) -> Character? {
        let peek = body.index(current, offsetBy: idx)
        guard peek < body.endIndex else { return nil }
        return body[peek]
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard current < body.endIndex else { return nil }
        column = body[current] == .newLine ? 1 : column + 1
        line += body[current] == .newLine ? 1 : 0
        defer { current = body.index(after: current) }
        return body[current]
    }

    mutating func pop(count: Int) -> String {
        var result = ""
        for _ in 0..<count { result += pop()?.description ?? "" }
        return result
    }

    // MARK: - Private Only

    private(set) var line = 1
    private(set) var column = 1

    private let body: String
    private var current: String.Index

    mutating private func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> String {
        var str = [Character]()
        str.reserveCapacity(max(64,body.count/4)) // Buffer guess -
        while let next = peek() {
            guard check(next) else { return String(str) }
            if pop { self.pop() }
            str.append(next)
        }
        return String(str)
    }

    mutating private func peekSliceWhile(_ check: (Character) -> Bool) -> String {
        var str = [Character]()
        str.reserveCapacity(max(64,body.count/4))
        var index = 0
        while let next = peek(aheadBy: index) {
            guard check(next) else { return String(str) }
            str.append(next)
            index += 1
        }
        return String(str)
    }
}
