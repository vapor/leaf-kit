// FIXME: Should really be initializable directly from `ByteBuffer`
// TODO: Make `LeafSource` return this instead of `ByteBuffer` via extension

public typealias SourceLocation = (name: String, line: Int, column: Int)

/// Convenience wrapper around a `String` raw source to track line & column, pop, peek & scan.
internal struct LKRawTemplate {
    // MARK: - Internal Only
    var state: SourceLocation
    
    init(_ name: String, _ source: String) {
        self.state = (name, 1, 1)
        self.body = source
        self.current = body.startIndex
    }

    mutating func readWhile(_ check: (Character) -> Bool) -> String {
        readSliceWhile(check) }

    @discardableResult
    mutating func readWhileNot(_ check: Set<Character>) -> String {
        readSliceWhile({!check.contains($0)}) }

    mutating func peekWhile(_ check: (Character) -> Bool) -> String {
        peekSliceWhile(check) }

    @discardableResult
    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        readSliceWhile(check).count }

    func peek(aheadBy idx: Int = 0) -> Character? {
        let peek = body.index(current, offsetBy: idx)
        return peek < body.endIndex ? body[peek] : nil
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard current < body.endIndex else { return nil }
        state.column = body[current] == .newLine ? 1 : state.column + 1
        state.line += body[current] == .newLine ? 1 : 0
        defer { current = body.index(after: current) }
        return body[current]
    }

    // MARK: - Private Only
    private let body: String
    private var current: String.Index

    mutating private func readSliceWhile(_ check: (Character) -> Bool) -> String {
        var str: [Character] = []
        str.reserveCapacity(64)
        while let next = peek(), check(next) { str.append(pop()!) }
        return String(str)
    }

    mutating private func peekSliceWhile(_ check: (Character) -> Bool) -> String {
        var str: [Character] = []
        str.reserveCapacity(64)
        var index = 0
        while let next = peek(aheadBy: index), check(next) {
            str.append(next)
            index += 1
        }
        return String(str)
    }
}
