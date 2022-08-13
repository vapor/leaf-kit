import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit
import NIO

func assertSExprEqual(_ left: String, _ right: String, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(
        left.filter { !$0.isWhitespace },
        right.filter { !$0.isWhitespace },
        file: file,
        line: line
    )
}
func assertSExpr(_ data: String, _ sexpr: String, file: StaticString = #file, line: UInt = #line) throws {
    let scanner = LeafScanner(name: "Hello World", source: data)
    let parser = LeafParser(from: scanner)
    let statements = try parser.parse()
    assertSExprEqual(statements.sexpr(), sexpr, file: file, line: line)
}

final class LeafParserTests: XCTestCase {
    func testBasics() throws {
        try assertSExpr(
            """
            roses are #(red) violets are #blue
            """,
            """
            (raw)
            (substitution (variable))
            (raw)
            (tag)
            """
        )
    }
    func testConditionals2() throws {
        try assertSExpr(
            """
            #if(false):#(true)#elseif(true):Good#else:#(true)#endif
            """,
            """
            (conditional (false)
                onTrue: (substitution (true))
                onFalse: (conditional (true)
                    onTrue:(raw)
                    onFalse:(substitution(true))))
            """
        )
    }
    func testConditionals() throws {
        try assertSExpr(
            """
            #if(true):
            hi
            #else:
            hi
            #endif
            """,
            """
            (conditional (true)
                onTrue: (raw)
                onFalse: (raw))
            """
        )
    }
    func testGrouping() throws {
        try assertSExpr(
            """
            #(!true || !false)
            """,
            """
            (substitution
                (||
                    (! (true))
                    (! (false))))
            """
        )
    }
    func testGroupingTwo() throws {
        // 1 == 1 + 1 || 1 == 2 - 1
        // should be equivalent to
        // ((1 == (1 + 1)) || (1 == (2 - 1)))

        let sexpr = """
            (substitution
                (||
                    (== (integer) (+ (integer) (integer)))
                    (== (integer) (- (integer) (integer)))))
            """

        try assertSExpr(
            """
            #(1 == 1 + 1 || 1 == 2 - 1)
            """,
            sexpr
        )
        try assertSExpr(
            """
            #((1 == (1 + 1)) || (1 == (2 - 1)))
            """,
            sexpr
        )
    }
}
