struct LeafRawTemplate {
    // MARK: - Internal Only
    let name: String
    
    init(name: String, src: String) {
        self.name = name
        self.body = src
        self.current = body.startIndex
    }

    mutating func readWhile(_ check: (Character) -> Bool) -> String {
        .init(self.readSliceWhile(pop: true, check))
    }

    mutating func peekWhile(_ check: (Character) -> Bool) -> String {
        .init(self.peekSliceWhile(check))
    }
    
    @discardableResult
    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        self.readSliceWhile(pop: true, check).count
    }

    func peek(aheadBy idx: Int = 0) -> Character? {
        let peekIndex = self.body.index(self.current, offsetBy: idx)
        guard peekIndex < self.body.endIndex else {
            return nil
        }
        return self.body[peekIndex]
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard self.current < self.body.endIndex else {
            return nil
        }
        if self.body[self.current] == .newLine {
            self.line += 1
            self.column = 0
        } else {
            self.column += 1
        }
        defer { self.current = self.body.index(after: self.current) }
        return self.body[self.current]
    }
    
    // MARK: - Private Only
    
    private(set) var line = 0
    private(set) var column = 0

    private let body: String
    private var current: String.Index
    
    mutating private func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        while let next = self.peek() {
            guard check(next) else {
                return str
            }
            if pop {
                self.pop()
            }
            str.append(next)
        }
        return str
    }

    mutating private func peekSliceWhile(_ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        var index = 0
        while let next = self.peek(aheadBy: index) {
            guard check(next) else {
                return str
            }
            str.append(next)
            index += 1
        }
        return str
    }
}
