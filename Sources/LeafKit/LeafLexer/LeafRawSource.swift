/// `TemplateSource` was ambiguous - renamed to `LeafRawTemplate` and make
/// `LeafFiles` (to also be renamed to `LeafSource`)  return it directly rather than a ByteBuffer
struct LeafRawTemplate {
    let name: String

    private(set) var line = 0
    private(set) var column = 0

    private var body: [Character]

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

    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        return readSliceWhile(pop: true, check).count
    }

    mutating func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        while let next = peek() {
            guard check(next) else { return str }
            if pop { self.pop() }
            str.append(next)
        }
        return str
    }

    mutating func peekSliceWhile(_ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        var index = 0
        while let next = peek(aheadBy: index) {
            guard check(next) else { return str }
            str.append(next)
            index += 1
        }
        return str
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
}
