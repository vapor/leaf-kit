import Testing

@testable import LeafKit

@Suite
struct PrintTests {
    @Test func testRaw() throws {
        let template = "hello, raw text"
        let expectation = "raw(\"hello, raw text\")"

        let v = try #require(parse(template).first)
        guard case .raw = v else { throw LeafError.unknownError("nope") }
        let output = v.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testVariable() throws {
        let template = "#(foo)"
        let expectation = "variable(foo)"

        let v = try #require(parse(template).first)
        guard case .expression(let e) = v,
            let test = e.first
        else { throw LeafError.unknownError("nope") }
        let output = test.description
        #expect(output == expectation)
    }

    @Test func testLoop() throws {
        let template = """
            #for(name in names):
                hello, #(name).
            #endfor
            """
        let expectation = """
            for(name in names):
              raw("\\n    hello, ")
              expression[variable(name)]
              raw(".\\n")
            """

        let v = try #require(parse(template).first)
        guard case .loop(let test) = v else { throw LeafError.unknownError("nope") }
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testLoopCustomIndex() throws {
        let template = """
            #for(i, name in names):
                #(i): hello, #(name).
            #endfor
            """
        let expectation = """
            for(i, name in names):
              raw("\\n    ")
              expression[variable(i)]
              raw(": hello, ")
              expression[variable(name)]
              raw(".\\n")
            """

        let v = try #require(parse(template).first)
        guard case .loop(let test) = v else { throw LeafError.unknownError("nope") }
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testConditional() throws {
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
            conditional:
              if(variable(foo)):
                raw("\\n    some stuff\\n")
              elseif([bar == "bar"]):
                raw("\\n    bar stuff\\n")
              else:
                raw("\\n    no stuff\\n")
            """

        let v = try #require(parse(template).first)
        guard case .conditional(let test) = v else { throw LeafError.unknownError("nope") }
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testImport() throws {
        let template = "#import(\"someimport\")"
        let expectation = "import(\"someimport\")"

        let v = try #require(parse(template).first)
        guard case .import(let test) = v else { throw LeafError.unknownError("nope") }
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testExtendAndExport() throws {
        let template = """
            #extend("base"):
                #export("title","Welcome")
                #export("body"):
                    hello there
                #endexport
            #endextend
            """
        let expectation = """
            extend("base"):
              export("body"):
                raw("\\n        hello there\\n    ")
              export("title"):
                expression[stringLiteral("Welcome")]
            """

        let v = try #require(parse(template).first)
        guard case .extend(let test) = v else { throw LeafError.unknownError("nope") }
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }

    @Test func testCustomTag() throws {
        let template = """
            #custom(tag, foo == bar):
                some body
            #endcustom
            """

        let v = try #require(parse(template).first)
        guard case .custom(let test) = v else { throw LeafError.unknownError("nope") }

        let expectation = """
            custom(variable(tag), [foo == bar]):
              raw("\\n    some body\\n")
            """
        let output = test.print(depth: 0)
        #expect(output == expectation)
    }
}
