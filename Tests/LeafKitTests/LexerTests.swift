import LeafKit
import Testing

@Suite
struct LexerTests {
    func testParamNesting() throws {
        let input = """
            #if(lowercase(first(name == "admin")) == "welcome"):
            foo
            #endif
            """

        let expectation = """
            tagIndicator
            tag(name: "if")
            parametersStart
            param(tag("lowercase"))
            parametersStart
            param(tag("first"))
            parametersStart
            param(variable(name))
            param(operator(==))
            param(stringLiteral("admin"))
            parametersEnd
            parametersEnd
            param(operator(==))
            param(stringLiteral("welcome"))
            parametersEnd
            tagBodyIndicator
            raw("\\nfoo\\n")
            tagIndicator
            tag(name: "endif")

            """

        let output = try lex(input).string
        #expect(output == expectation)
    }

    func testConstant() throws {
        let input = "<h1>#(42)</h1>"
        let expectation = """
            raw("<h1>")
            tagIndicator
            tag(name: "")
            parametersStart
            param(constant(42))
            parametersEnd
            raw("</h1>")

            """

        let output = try lex(input).string
        #expect(output == expectation)
    }

    func testNoWhitespace() throws {
        let input1 = "#if(!one||!two)"
        let input2 = "#if(!one || !two)"
        let input3 = "#if(! one||! two)"
        let input4 = "#if(! one || ! two)"

        let output1 = try lex(input1).string
        let output2 = try lex(input2).string
        let output3 = try lex(input3).string
        let output4 = try lex(input4).string
        #expect(output1 == output2)
        #expect(output2 == output3)
        #expect(output3 == output4)
    }

    // Base2/8/10/16 lexing for Int constants, Base10/16 for Double
    func testNonDecimals() throws {
        let input = "#(0b0101010 0o052 42 0_042 0x02A 0b0101010.0 0o052.0 42.0 0_042.0 0x02A.0)"
        let expectation = """
            tagIndicator
            tag(name: "")
            parametersStart
            param(constant(42))
            param(constant(42))
            param(constant(42))
            param(constant(42))
            param(constant(42))
            param(variable(0b0101010.0))
            param(variable(0o052.0))
            param(constant(42.0))
            param(constant(42.0))
            param(constant(42.0))
            parametersEnd

            """

        let output = try lex(input).string
        #expect(output == expectation)
    }

    func testEscaping() throws {
        // input is really '\#' w/ escaping
        let input = "\\#"
        let output = try lex(input).string
        #expect(output == "raw(\"#\")\n")
    }

    func testParameters() throws {
        let input = "#(foo == 40, and, \"literal\", and, foo_bar)"
        let expectation = """
            tagIndicator
            tag(name: "")
            parametersStart
            param(variable(foo))
            param(operator(==))
            param(constant(40))
            parameterDelimiter
            param(variable(and))
            parameterDelimiter
            param(stringLiteral("literal"))
            parameterDelimiter
            param(variable(and))
            parameterDelimiter
            param(variable(foo_bar))
            parametersEnd

            """
        let output = try lex(input).string
        #expect(output == expectation)
    }

    func testTags() throws {
        let input = """
            #tag
            #tag:
            #endtag
            #tag()
            #tag():
            #tag(foo)
            #tag(foo):
            """
        let expectation = """
            tagIndicator
            tag(name: "tag")
            raw("\\n")
            tagIndicator
            tag(name: "tag")
            tagBodyIndicator
            raw("\\n")
            tagIndicator
            tag(name: "endtag")
            raw("\\n")
            tagIndicator
            tag(name: "tag")
            parametersStart
            parametersEnd
            raw("\\n")
            tagIndicator
            tag(name: "tag")
            parametersStart
            parametersEnd
            tagBodyIndicator
            raw("\\n")
            tagIndicator
            tag(name: "tag")
            parametersStart
            param(variable(foo))
            parametersEnd
            raw("\\n")
            tagIndicator
            tag(name: "tag")
            parametersStart
            param(variable(foo))
            parametersEnd
            tagBodyIndicator

            """

        let output = try lex(input).string
        #expect(output == expectation)
    }

    func testNestedEcho() throws {
        let input = """
            #(todo)
            #(todo.title)
            #(todo.user.name.first)
            """
        let expectation = """
            tagIndicator
            tag(name: "")
            parametersStart
            param(variable(todo))
            parametersEnd
            raw("\\n")
            tagIndicator
            tag(name: "")
            parametersStart
            param(variable(todo.title))
            parametersEnd
            raw("\\n")
            tagIndicator
            tag(name: "")
            parametersStart
            param(variable(todo.user.name.first))
            parametersEnd

            """
        let output = try lex(input).string
        #expect(output == expectation)
    }
}
