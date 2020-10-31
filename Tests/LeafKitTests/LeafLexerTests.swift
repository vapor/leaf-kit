@testable import XCTLeafKit
@testable import LeafKit

final class LexerTests: MemoryRendererTestCase {
    func testParamNesting() throws {
        let template = """
        #if(lowercase(first(name == "admin")) == "welcome"):
        foo
        #endif
        """

        let expectation = """
        tagIndicator
        function("if")
        parametersStart
        parameter(function(id: "lowercase"))
        parametersStart
        parameter(function(id: "first"))
        parametersStart
        parameter(variable(part: name))
        parameter(operator(Equality: ==))
        parameter(literal(String: "admin"))
        parametersEnd
        parametersEnd
        parameter(operator(Equality: ==))
        parameter(literal(String: "welcome"))
        parametersEnd
        blockIndicator
        raw("\\nfoo\\n")
        tagIndicator
        function("endif")
        
        """

        try XCTAssertEqual(lex(raw: template).string, expectation)
    }

    func testConstant() throws {
        let expectation = """
        raw("<h1>")
        tagIndicator
        expression
        parametersStart
        parameter(literal(Int: 42))
        parametersEnd
        raw("</h1>")
        
        """

        try XCTAssertEqual(lex(raw: "<h1>#(42)</h1>").string, expectation)
    }

    // Base2/8/10/16 lexing for Int constants, Base10/16 for Double
    func testNonDecimals() throws {
        let template = "#(0b0101010 0o052 42 0_042 0x02A 42.0 0_042.0 0x02A.0)"
        let expectation = """
        tagIndicator
        expression
        parametersStart
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Int: 42))
        parameter(literal(Double: 42.0))
        parameter(literal(Double: 42.0))
        parameter(literal(Double: 42.0))
        parametersEnd

        """

        try XCTAssertEqual(lex(raw: template).string, expectation)
    }

    func testEscaping() throws {
        try XCTAssertEqual(lex(raw: "\\#").string, "raw(\"#\")\n")
    }

    func testTagIndicator() throws {
        LKConf.tagIndicator = "🤖"
        let template = """
        🤖let(title = "Welcome")
        🤖define(body):
            Hello, 🤖(name)!
        🤖enddefine
        🤖inline("base")
        """

        let expectation = """
        0: [let $:title string(Welcome)]
        2: define(body):
        3: scope(table: 1)
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
        5: inline("base", leaf):
        6: scope(undefined)
        """

        try! XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testParameters() throws {
        let template = #"#(foo == 40, and, "literal", and, foo_bar)"#
        let expectation = """
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: foo))
        parameter(operator(Equality: ==))
        parameter(literal(Int: 40))
        parameterDelimiter
        parameter(variable(part: and))
        parameterDelimiter
        parameter(literal(String: "literal"))
        parameterDelimiter
        parameter(variable(part: and))
        parameterDelimiter
        parameter(variable(part: foo_bar))
        parametersEnd

        """
        
        try XCTAssertEqual(lex(raw: template).string, expectation)
    }

    func testTags() throws {
        let template = """
        #enddefine
        #define()
        #define():
        #define(foo)
        #define(foo):
        """
        let expectation = """
        tagIndicator
        function("enddefine")
        tagIndicator
        function("define")
        parametersStart
        parametersEnd
        tagIndicator
        function("define")
        parametersStart
        parametersEnd
        blockIndicator
        tagIndicator
        function("define")
        parametersStart
        parameter(variable(part: foo))
        parametersEnd
        tagIndicator
        function("define")
        parametersStart
        parameter(variable(part: foo))
        parametersEnd
        blockIndicator

        """

        try XCTAssertEqual(lex(raw: template).string, expectation)
    }

    func testNestedEcho() throws {
        let template = """
        #(todo)
        #(todo.title)
        #(todo.user.name.first)
        """
        let expectation = """
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: todo))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: todo))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: title))
        parametersEnd
        tagIndicator
        expression
        parametersStart
        parameter(variable(part: todo))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: user))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: name))
        parameter(operator(Scoping Accessor: .))
        parameter(variable(part: first))
        parametersEnd

        """
        
        try XCTAssertEqual(lex(raw: template).string, expectation)
    }
}
