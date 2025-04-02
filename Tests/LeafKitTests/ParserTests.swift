import Testing

@testable import LeafKit

@Suite
struct ParserTests {
    func testParsingNesting() throws {
        let input = """
            #if(lowercase(first(name == "admin")) == "welcome"):
            foo
            #endif
            """

        let expectation = """
            conditional:
              if([lowercase(first([name == "admin"])) == "welcome"]):
                raw("\\nfoo\\n")
            """

        let output = try parse(input).string
        #expect(output == expectation)
    }

    func testComplex() throws {
        let input = """
            #if(foo):
            foo
            #else:
            foo
            #endif
            """

        let expectation = """
            conditional:
              if(variable(foo)):
                raw("\\nfoo\\n")
              else:
                raw("\\nfoo\\n")
            """

        let output = try parse(input).string
        #expect(output == expectation)
    }

    func testCompiler() throws {
        let input = """
            #if(sayhello):
                abc
                #for(name in names):
                    hi, #(name)
                #endfor
                def
            #else:
                foo
            #endif
            """

        let expectation = """
            conditional:
              if(variable(sayhello)):
                raw("\\n    abc\\n    ")
                for(name in names):
                  raw("\\n        hi, ")
                  expression[variable(name)]
                  raw("\\n    ")
                raw("\\n    def\\n")
              else:
                raw("\\n    foo\\n")
            """

        let output = try parse(input).string
        #expect(output == expectation)
    }

    func testUnresolvedAST() throws {
        let base = """
            #extend("header")
            <title>#import("title")</title>
            #import("body")
            """

        let syntax = try parse(base)
        let ast = LeafAST(name: "base", ast: syntax)
        #require(ast.unresolvedRefs.count != 0, "Unresolved template")
    }

    func testInsertResolution() throws {
        let header = """
            <h1>Hi!</h1>
            """
        let base = """
            #extend("header")
            <title>#import("title")</title>
            #import("body")
            """

        let baseAST = try LeafAST(name: "base", ast: parse(base))
        let headerAST = try LeafAST(name: "header", ast: parse(header))
        let baseResolvedAST = LeafAST(from: baseAST, referencing: ["header": headerAST])

        let output = baseResolvedAST.ast.string

        let expectation = """
            raw("<h1>Hi!</h1>\\n<title>")
            import("title")
            raw("</title>\\n")
            import("body")
            """
        #expect(output == expectation)
    }

    func testDocumentResolveExtend() throws {
        let header = """
            <h1>#import("header")</h1>
            """

        let base = """
            #extend("header")
            <title>#import("title")</title>
            #import("body")
            """

        let home = """
            #extend("base"):
                #export("title", "Welcome")
                #export("body"):
                    Hello, #(name)!
                #endexport
            #endextend
            """

        let headerAST = try LeafAST(name: "header", ast: parse(header))
        let baseAST = try LeafAST(name: "base", ast: parse(base))
        let homeAST = try LeafAST(name: "home", ast: parse(home))

        let baseResolved = LeafAST(from: baseAST, referencing: ["header": headerAST])
        let homeResolved = LeafAST(from: homeAST, referencing: ["base": baseResolved])

        let output = homeResolved.ast.string
        let expectation = """
            raw("<h1>")
            import("header")
            raw("</h1>\\n<title>Welcome</title>\\n\\n        Hello, ")
            expression[variable(name)]
            raw("!\\n    ")
            """
        #expect(output == expectation)
    }

    func testCompileExtend() throws {
        let input = """
            #extend("base"):
                #export("title", "Welcome")
                #export("body"):
                    Hello, #(name)!
                #endexport
            #endextend
            """

        let expectation = """
            extend("base"):
              export("body"):
                raw("\\n        Hello, ")
                expression[variable(name)]
                raw("!\\n    ")
              export("title"):
                expression[stringLiteral("Welcome")]
            """

        let output = try parse(input).string
        #expect(output == expectation)
    }
}
