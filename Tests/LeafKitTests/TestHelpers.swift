@testable import XCTLeafKit
@testable import LeafKit

/// Assorted multi-purpose helper pieces for LeafKit tests
// MARK: - Helper Extensions

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array where Element == LKToken {
    var string: String {
        compactMap { if case .whiteSpace(_) = $0.token { return nil }
                     else if $0.token == .raw("\n") { return nil }
                     return $0.description + "\n" }.reduce("", +) }
}

// MARK: - Helper Variables

/// Automatic path discovery for the Templates folder in this package
var templateFolder: String { projectTestFolder + "Templates/" }
var projectTestFolder: String { "/\(#file.split(separator: "/").dropLast().joined(separator: "/"))/"}

// MARK: - Internal Tests

/// Test printing descriptions of Syntax objects
final class PrintTests: MemoryRendererTestCase {
    func testRaw() throws {
        try XCTAssertEqual(parse(raw: "hello, raw text").terse,
                           "0: raw(LeafBuffer: 15B)")
    }

    func testPassthrough() throws {
        try XCTAssertEqual(parse(raw: "#(foo)").terse, "0: $:foo")
    }

    func testLoop() throws {
        let template = """
        #for(name in names):
            hello, #(name).
        #endfor
        """
        
        let expectation = """
        0: for($:names):
        1: scope(table: 1)
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
        """
        
        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testConditional() throws {
        let template = """
        #if(foo):
            some stuff
        #elseif(bar == "bar"):
            bar stuff
        #else:
            no stuff
        #endif
        """
        
        let expectation = """
        0: if($:foo):
        1: raw(LeafBuffer: 16B)
        2: elseif([$:bar == string(bar)]):
        3: raw(LeafBuffer: 15B)
        4: else:
        5: raw(LeafBuffer: 14B)
        """
        
        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testImport() throws {
        let template = "#evaluate(someimport)"
        let expectation = """
        0: evaluate(someimport):
        1: scope(undefined)
        """
        
        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testExtendAndExport() throws {
        LKROption.missingVariableThrows = false
        LKROption.parseWarningThrows = false
        
        let template = """
        #define(title = "Welcome")
        #define(body):
            hello there
        #enddefine
        #inline("base")
        """
        let expectation = """
        0: define(title):
        1: string(Welcome)
        3: define(body):
        4: raw(LeafBuffer: 17B)
        6: inline("base", leaf):
        7: scope(undefined)
        """
        
        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }
    
    func testValidateStringAsLeaf() throws {
        let tests: [(String, Result<Bool, String>)] = [
            ("A sample with no Leaf", .success(false)),
            ("A sample with \\#ecapedTagIndicators", .success(false)),
            ("A sample with #(anonymous) tag", .success(true)),
            ("A sample with #define(valid) tag usage", .success(true)),
            ("A sample with #enddefine closing tag usage", .success(true)),
            ("A sample with #notAValid() tag usage", .failure("")),
            ("A cropped #samp", .failure("#samp")),
            ("A sample with an ending mark#", .failure("#"))
        ]
        
        for i in tests.indices {
            XCTAssertEqual(tests[i].0.isLeafProcessable(.leaf4Core), tests[i].1)
        }
    }
}

struct Stopwatch {
    var total: String { _total.formatSeconds() }
    var average: String { (_total / Double(_laps)).formatSeconds() }
    
    mutating func start() { _laps = 0; _total = 0.0; _lap = Date() }
    
    @discardableResult
    mutating func lap(accumulate: Bool = false) -> String {
        let x = _lap
        _lap = Date()
        if accumulate { _laps += 1; _total += x +-> _lap }
        return (x +-> _lap).formatSeconds() }
    
    private(set) var _total = 0.0
    private var _lap: Date = Date()
    private var _laps: Int = 0
}

// MARK: For `testContexts()`
class _APIVersioning: LeafContextPublisher {
    init(_ a: String, _ b: (Int, Int, Int)) { self.identifier = a; self.version = b }
    
    let identifier: String
    var version: (major: Int, minor: Int, patch: Int)

    lazy private(set) var leafVariables: [String: LeafDataGenerator] = [
        "identifier" : .immediate(identifier),
        "version"    : .lazy(["major": self.version.major,
                              "minor": self.version.minor,
                              "patch": self.version.patch])
    ]
}

extension _APIVersioning {
    var extendedVariables: [String: LeafDataGenerator] {[
        "isRelease": .lazy(self.version.major > 0)
    ]}
}
