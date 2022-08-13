import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit
import NIO

final class ScannerTests: XCTestCase {
    func testBasics() throws {
        let scanner = LeafScanner(name: "Hello World", source: "roses are #red violets are #blue")
        let tokens: [LeafScanner.Token] = [.raw("roses are "), .tag(name: "red"), .raw(" violets are "), .tag(name: "blue")]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
    func testModeSwitch() throws {
        let scanner = LeafScanner(name: "Hello World", source: "roses are #red((5)) violets are #blue(5.0)")
        let tokens: [LeafScanner.Token] = [
            .raw("roses are "), 
            .tag(name: "red"),
            .enterExpression,
            .expression(.leftParen),
            .expression(.integer(base: 10, digits: "5")),
            .expression(.rightParen),
            .exitExpression,
            .raw(" violets are "),
            .tag(name: "blue"),
            .enterExpression,
            .expression(.decimal(base: 10, digits: "5.0")),
            .exitExpression,
        ]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
    func testNumbers() throws {
        let scanner = LeafScanner(name: "Hello World", source: "#red(5) #red(5.0) #red(0xA)")
        let tokens: [LeafScanner.Token] = [
            .tag(name: "red"),
            .enterExpression,
            .expression(.integer(base: 10, digits: "5")),
            .exitExpression,
            .raw(" "),
            .tag(name: "red"),
            .enterExpression,
            .expression(.decimal(base: 10, digits: "5.0")),
            .exitExpression,
            .raw(" "),
            .tag(name: "red"),
            .enterExpression,
            .expression(.integer(base: 16, digits: "A")),
            .exitExpression,
        ]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
    func testWhitespace() throws {
        let scanner = LeafScanner(name: "Hello World", source: "#red(  5  )e")
        let tokens: [LeafScanner.Token] = [
            .tag(name: "red"),
            .enterExpression,
            .expression(.integer(base: 10, digits: "5")),
            .exitExpression,
            .raw("e"),
        ]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
    func testOperators() throws {
        let scanner = LeafScanner(name: "Hello World", source: "#red(5+2&&3)e")
        let tokens: [LeafScanner.Token] = [
            .tag(name: "red"),
            .enterExpression,
            .expression(.integer(base: 10, digits: "5")),
            .expression(.operator(.plus)),
            .expression(.integer(base: 10, digits: "2")),
            .expression(.operator(.and)),
            .expression(.integer(base: 10, digits: "3")),
            .exitExpression,
            .raw("e"),
        ]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
    func testComplex() throws {
        let scanner = LeafScanner(name: "Hello World", source: """
        #extend("base"):
            #export("body"):
            Snippet added through export/import
            #extend("partials/picture.svg"):#endextend
        #endexport
        #endextend
        """)
        let tokens: [LeafScanner.Token] = [
            .tag(name: "extend"),
            .enterExpression,
            .expression(.stringLiteral("base")),
            .exitExpression,
            .bodyStart,
            .raw("\n    "),
            .tag(name: "export"),
            .enterExpression,
            .expression(.stringLiteral("body")),
            .exitExpression,
            .bodyStart,
            .raw("\n    Snippet added through export/import\n    "),
            .tag(name: "extend"),
            .enterExpression,
            .expression(.stringLiteral("partials/picture.svg")),
            .exitExpression,
            .bodyStart,
            .tag(name: "endextend"),
            .raw("\n"),
            .tag(name: "endexport"),
            .raw("\n"),
            .tag(name: "endextend")
        ]
        XCTAssertEqual(try scanner.scanAll().tokensOnly(), tokens)
    }
}