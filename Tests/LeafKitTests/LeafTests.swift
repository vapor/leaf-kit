@testable import LeafKit
import XCTest

final class LeafTests: XCTestCase {

    // conversation ongoing
    func testCommentSugar() throws {
        let template = """
        #("foo")
        #comment:
            this is a comment!
        #endcomment
        bar
        """
        try XCTAssertEqual(render(template), "foo\n\nbar")
    }

    func testHashtag() throws {
        let template = """
        #("hi") #thisIsNotATag...
        """
        try XCTAssertEqual(render(template), "hi #thisIsNotATag...")
    }

    // conversation ongoing
    func testComplexIf() throws {
        let template = """
        #if(a): #if(b): hallo #else: #if(c): dallo #else: ballo #endif #endif #endif
        """

        let expectation = """
        ballo
        """
        let rendered = try render(template, ["a": .string("true")])
        XCTAssertEqual(
            rendered.trimmingCharacters(in: .whitespacesAndNewlines),
            expectation.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testRaw() throws {
        let template = "Hello!"
        try XCTAssertEqual(render(template), "Hello!")
    }

    func testPrint() throws {
        let template = "Hello, #(name)!"
        try XCTAssertEqual(render(template, ["name": "Tanner"]), "Hello, Tanner!")
    }

    func testConstant() throws {
        let template = "<h1>#(42)</h1>"
        try XCTAssertEqual(render(template), "<h1>42</h1>")
    }

    func testNested() throws {
        let template = """
        <p>#(lowercased(foo))</p>
        """
        try XCTAssertEqual(render(template, ["foo": "BAR"]), "<p>bar</p>")
    }

    func testExpression() throws {
        let template = "#(age > 99)"
        try XCTAssertEqual(render(template, ["age": 21]), "false")
        try XCTAssertEqual(render(template, ["age": 150]), "true")
    }

    func testBody() throws {
        let template = """
        #if(show):hi#endif
        """
        try XCTAssertEqual(render(template, ["show": false]), "")
        try XCTAssertEqual(render(template, ["show": true]), "hi")
    }

    func testForSugar() throws {
        let template = """
        <p>
            <ul>
                #for(name in names):<li>#(name)</li>#endfor
            </ul>
        </p>
        """
        let expect = """
        <p>
            <ul>
                <li>Vapor</li><li>Leaf</li><li>Bits</li>
            </ul>
        </p>
        """
        try XCTAssertEqual(render(template, ["names": ["Vapor", "Leaf", "Bits"]]), expect)
    }

    func testIfSugar() throws {
        let template = """
        #if(false):Bad#elseif(true):Good#else:Bad#endif
        """
        try XCTAssertEqual(render(template), "Good")
    }

    func testNot() throws {
        let template = """
        #if(!false):Good#endif#if(!true):Bad#endif
        """
        try XCTAssertEqual(render(template), "Good")
    }

    func testNestedBodies() throws {
        let template = """
        #if(true):#if(true):Hello#endif#endif
        """
        try XCTAssertEqual(render(template), "Hello")
    }

    func testDotSyntax() throws {
        let template = """
        #if(user.isAdmin):Hello, #(user.name)!#endif
        """
        try XCTAssertEqual(render(template, ["user": ["isAdmin": true, "name": "Tanner"]]), "Hello, Tanner!")
    }

    func testEqual() throws {
        let template = """
        #if(id == 42):User 42!#endif#if(id != 42):Shouldn't show up#endif
        """
        try XCTAssertEqual(render(template, ["id": 42, "name": "Tanner"]), "User 42!")
    }

    func testStringIf() throws {
        let template = """
        #if(name):Hello, #(name)!#else:No Name!#endif
        """
        let expectedName = "Hello, Tanner!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testEqualIf() throws {
        let template = """
        #if(string1 == string2):Good#else:Bad#endif
        """
        let expectedGood = "Good"
        let expectedBad = "Bad"
        try XCTAssertEqual(render(template, ["string1": .string("Tanner"), "string2": .string("Tanner")]), expectedGood)
        try XCTAssertEqual(render(template, ["string1": .string("Tanner"), "string2": .string("n/a")]), expectedBad)
    }

    func testAndStringIf() throws {
        let template = """
        #if(name && one):Hello, #(name)#(one)!#elseif(name):Hello, #(name)!#else:No Name!#endif
        """
        let expectedNameOne = "Hello, Tanner1!"
        let expectedName = "Hello, Tanner!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner"), "one": .string("1")]), expectedNameOne)
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testOrStringIf() throws {
        let template = """
        #if(name || one):Hello, #(name)#(one)!#else:No Name!#endif
        """
        let expectedName = "Hello, Tanner!"
        let expectedOne = "Hello, 1!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template, ["one": .string("1")]), expectedOne)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testArrayIf() throws {
        let template = """
        #if(namelist):#for(name in namelist):Hello, #(name)!#endfor#else:No Name!#endif
        """
        let expectedName = "Hello, Tanner!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["namelist": [.string("Tanner")]]), expectedName)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testEscapeTag() throws {
        let template = """
        #("foo") \\#("bar")
        """
        let expected = """
        foo #("bar")
        """
        try XCTAssertEqual(render(template, [:]), expected)
    }

    func testEscapingQuote() throws {
        let template = """
        #("foo $"bar$"")
        """
        let expected = """
        foo "bar"
        """
        try XCTAssertEqual(render(template), expected)
    }

    func testCount() throws {
        let template = """
        count: #count(array)
        """
        let expected = """
        count: 4
        """
        try XCTAssertEqual(render(template, ["array": ["","","",""]]), expected)
    }

    func testDateFormat() throws {
        let template = """
        Date: #date(foo, "yyyy-MM-dd")
        """

        let expected = """
        Date: 1970-01-16
        """
        try XCTAssertEqual(render(template, ["foo": 1_337_000]), expected)

    }

    func testWith() throws {
        let template = """
        #with(parent):#(child)#endwith
        """
        let expected = """
        Elizabeth
        """

        try XCTAssertEqual(render(template, ["parent": ["child": "Elizabeth"]]), expected)
    }

    func testExtendWithSugar() throws {
        let header = """
        <h1>#(child)</h1>
        """

        let base = """
        #extend("header", parent)
        """

        let expected = """
        <h1>Elizabeth</h1>
        """

        let headerAST = try LeafAST(name: "header", ast: parse(header))
        let baseAST = try LeafAST(name: "base", ast: parse(base))

        let baseResolved = LeafAST(from: baseAST, referencing: ["header": headerAST])

        var serializer = LeafSerializer(
            ast: baseResolved.ast,
            ignoreUnfoundImports: false
        )
        let view = try serializer.serialize(context: ["parent": ["child": "Elizabeth"]])
        let str = view.getString(at: view.readerIndex, length: view.readableBytes) ?? ""

        XCTAssertEqual(str, expected)
    }

    func testEmptyForLoop() throws {
        let template = """
        #for(category in categories):
            <a class=“dropdown-item” href=“#”>#(category.name)</a>
        #endfor
        """
        let expected = """
        """

        struct Category: Encodable {
            var name: String
        }

        struct Context: Encodable {
            var categories: [Category]
        }
        
        try XCTAssertEqual(render(template, ["categories": []]), expected)

    }

    func testKeyEqual() throws {
        let template = """
        #if(title == "foo"):it's foo#else:not foo#endif
        """
        let expected = """
        it's foo
        """

        struct Stuff: Encodable {
            var title: String
        }

        try XCTAssertEqual(render(template, ["title": "foo"]), expected)
    }

    func testLoopIndices() throws {
        let template = """
        #for(name in names):
            #(name) - index=#(index) last=#(isLast) first=#(isFirst)
        #endfor
        """
        let expected = """

            tanner - index=0 last=false first=true

            ziz - index=1 last=false first=false

            vapor - index=2 last=true first=false

        """

        try XCTAssertEqual(render(template, ["names": ["tanner", "ziz", "vapor"]]), expected)
    }

    func testNestedLoopIndices() throws {
        let template = """
        #for(array in arrays):
        Array#(index) - [#for(element in array): #(index)#if(isFirst):(first)#elseif(isLast):(last)#endif : "#(element)"#if(!isLast):, #endif#endfor]#endfor
        """
        let expected = """

        Array0 - [ 0(first) : "zero",  1 : "one",  2(last) : "two"]
        Array1 - [ 0(first) : "a",  1 : "b",  2(last) : "c"]
        Array2 - [ 0(first) : "red fish",  1 : "blue fish",  2(last) : "green fish"]
        """

        let data = LeafData.array([
            LeafData.array(["zero", "one", "two"]),
            LeafData.array(["a", "b", "c"]),
            LeafData.array(["red fish", "blue fish", "green fish"])
        ])

        try XCTAssertEqual(render(template, ["arrays": data]), expected)
    }

    func testNestedLoopCustomIndices() throws {
        let template = """
        #for(i, array in arrays):#for(j, element in array):
        (#(i), #(j)): #(element)#endfor#endfor
        """

        let expected = """

        (0, 0): zero
        (0, 1): one
        (0, 2): two
        (1, 0): a
        (1, 1): b
        (1, 2): c
        (2, 0): red fish
        (2, 1): blue fish
        (2, 2): green fish
        """

        let data = LeafData.array([
            LeafData.array(["zero", "one", "two"]),
            LeafData.array(["a", "b", "c"]),
            LeafData.array(["red fish", "blue fish", "green fish"])
        ])

        try XCTAssertEqual(render(template, ["arrays": data]), expected)
    }

    // It would be nice if a pre-render phase could catch things like calling
    // tags that would normally ALWAYS throw in serializing (eg, calling index
    // when not in a loop) so that warnings can be provided and AST can be minimized.
    func testLoopTagsInvalid() throws {
        let template = """
            #if(isFirst):Wrong#else:Right#endif
            """
            let expected = "Right"

        try XCTAssertEqual(render(template, [:]), expected)
    }

    // Current implementation favors context keys over tag keys, so
    // defining a key for isFirst in context will override accessing registered
    // LeafTags with the same name.
    // More reason to introduce scoping tag keys!!
    func testTagContextOverride() throws {
        let template = """
            #if(isFirst):Wrong (Maybe)#else:Right#endif
            """
            let expected = "Wrong (Maybe)"

        try XCTAssertEqual(render(template, ["isFirst": true]), expected)
    }
  
    // Validate parse resolution of negative numbers
    func testNegatives() throws {
        let input = """
        #(10)
        #(-10)
        """

        let syntax = """
        raw("10")
        raw("-10")
        """

        let expectation = """
        10
        -10
        """

        let parsed = try parse(input)
            .compactMap { $0.description != "raw(\"\\n\")" ? $0.description : nil }
            .joined(separator: "\n")
        XCTAssertEqual(parsed, syntax)
        try XCTAssertEqual(render(input), expectation)
    }

    // Validate parse resolution of evaluable expressions
    func testComplexParameters() throws {
        let input = """
        #(index-5)
        #(10-5)
        #(10 - 5)
        #(-5)
        """

        let syntax = """
        expression[variable(index), operator(-), constant(5)]
        expression[constant(10), operator(-), constant(5)]
        expression[constant(10), operator(-), constant(5)]
        raw("-5")
        """

        let expectation = """
        5
        5
        5
        -5
        """

        let parsed = try parse(input)
            .compactMap { $0.description != "raw(\"\\n\")" ? $0.description : nil }
            .joined(separator: "\n")
        XCTAssertEqual(parsed, syntax)
        try XCTAssertEqual(render(input,["index":10]), expectation)
    }

    // Validate parse resolution of negative numbers
    func testOperandGrouping() throws {
        let input = """
        #(!true&&!false)
        #((!true) || (!false))
        #((true) && (!false))
        #((!true) || (false))
        #(!true || !false)
        #(true)
        #(-5 + 10 - 20 / 2 + 9 * -3 == 90 / 3 + 0b010 * -0xA)
        """

        let syntax = """
        expression[keyword(false), operator(&&), keyword(true)]
        expression[keyword(false), operator(||), keyword(true)]
        expression[keyword(true), operator(&&), keyword(true)]
        expression[keyword(false), operator(||), keyword(false)]
        expression[keyword(false), operator(||), keyword(true)]
        raw("true")
        expression[[-5 + [10 - [[20 / 2] + [9 * -3]]]], operator(==), [[90 / 3] + [2 * -10]]]
        """

        let expectation = """
        false
        true
        true
        false
        true
        true
        false
        """

        let parsed = try parse(input)
            .compactMap { $0.description != "raw(\"\\n\")" ? $0.description : nil }
            .joined(separator: "\n")
        XCTAssertEqual(parsed, syntax)
        try XCTAssertEqual(render(input), expectation)
    }
}
